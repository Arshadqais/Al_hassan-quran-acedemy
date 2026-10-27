"""One-worker authenticated change notifications. Message text stays in PostgreSQL."""

import asyncio
import json
from collections import defaultdict
from contextlib import suppress
import os
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.security import HTTPAuthorizationCredentials
from app.db.database import env
from app.security import db, current_user

router = APIRouter()
_listeners = defaultdict(set)
CHECK_INTERVAL = 15


def notify_messages(*user_ids):
    for user_id in set(user_ids):
        for queue in tuple(_listeners.get(user_id, ())):
            if not queue.full():
                queue.put_nowait({"type": "messages_changed"})


@router.websocket("/api/ws/messages")
async def message_events(socket: WebSocket, session=Depends(db)):
    origins = {
        v.strip()
        for v in os.environ.get(
            "ACADEMY_ORIGINS", env.get("ACADEMY_ORIGINS", "")
        ).split(",")
        if v.strip()
    }
    origin = socket.headers.get("origin")
    if origin and origin not in origins:
        await socket.close(code=4403)
        return
    await socket.accept()
    queue = None
    user_id = None
    try:
        # Tokens are in a first frame, never in query strings or access logs.
        frame = await asyncio.wait_for(socket.receive(), timeout=5)
        if frame["type"] == "websocket.disconnect":
            raise WebSocketDisconnect()
        first = frame.get("text")
        if not isinstance(first, str) or len(first) > 1024:
            raise ValueError("Invalid authentication")
        payload = json.loads(first)
        if not isinstance(payload, dict):
            raise ValueError("Invalid authentication")
        token = payload.get("token", "")
        if not isinstance(token, str) or not 1 <= len(token) <= 512:
            raise ValueError("Invalid authentication")
        credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        user = await current_user(credentials, session)
        user_id = user.id
        await session.rollback()
        if len(_listeners[user_id]) >= 4:
            await socket.close(code=4429)
            return
        queue = asyncio.Queue(maxsize=1)
        _listeners[user_id].add(queue)
        await socket.send_json({"type": "ready"})
        while True:
            # A rollback expires cached user/session objects, so revocation,
            # inactive accounts and expiry take effect during open connections.
            await current_user(credentials, session)
            await session.rollback()
            message_task = asyncio.create_task(queue.get())
            receive_task = asyncio.create_task(socket.receive())
            try:
                done, _ = await asyncio.wait(
                    [message_task, receive_task],
                    timeout=CHECK_INTERVAL,
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if receive_task in done:
                    if receive_task.result()["type"] == "websocket.disconnect":
                        raise WebSocketDisconnect()
                    await socket.close(code=4400)
                    return
                await socket.send_json(
                    message_task.result()
                    if message_task in done
                    else {"type": "heartbeat"}
                )
            finally:
                for task in (message_task, receive_task):
                    task.cancel()
                    with suppress(asyncio.CancelledError, WebSocketDisconnect):
                        await task
    except (HTTPException, ValueError, TypeError, asyncio.TimeoutError):
        with suppress(RuntimeError, WebSocketDisconnect):
            await socket.close(code=4401)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if queue is not None:
            _listeners[user_id].discard(queue)
            if not _listeners[user_id]:
                _listeners.pop(user_id, None)
