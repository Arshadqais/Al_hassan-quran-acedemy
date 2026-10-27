import asyncio
import json
import socket
import pytest
import pytest_asyncio
import uvicorn
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus
from conftest import auth
from app.main import app
from app import realtime


@pytest_asyncio.fixture
async def server(client, monkeypatch):
    monkeypatch.setattr(realtime, "CHECK_INTERVAL", 0.1)
    monkeypatch.setenv("ACADEMY_ORIGINS", "http://academy-test.local")
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.setblocking(False)
    port = listener.getsockname()[1]
    service = uvicorn.Server(
        uvicorn.Config(app, log_level="critical", lifespan="off", ws_max_size=4096)
    )
    task = asyncio.create_task(service.serve(sockets=[listener]))
    for _ in range(200):
        if service.started:
            break
        if task.done():
            await task
        await asyncio.sleep(0.01)
    assert service.started
    yield f"ws://127.0.0.1:{port}/api/ws/messages"
    service.should_exit = True
    await asyncio.wait_for(task, 5)


async def authenticate(uri, headers):
    ws = await connect(uri, proxy=None, origin="http://academy-test.local")
    await ws.send(json.dumps({"token": headers["Authorization"][7:]}))
    assert json.loads(await ws.recv())["type"] == "ready"
    return ws


async def change_event(ws):
    while True:
        event = json.loads(await ws.recv())
        if event["type"] == "messages_changed":
            return event


@pytest.mark.asyncio
async def test_live_messages_are_persisted_and_notify_only_participants(client, server):
    teacher = await auth(client, 2)
    student = await auth(client, 3)
    parent = await auth(client, 4)
    t = await authenticate(server, teacher)
    s = await authenticate(server, student)
    p = await authenticate(server, parent)
    try:
        response = await client.post(
            "/api/messages",
            json={"recipient_id": 2, "text": "A live lesson question"},
            headers=student,
        )
        assert response.status_code == 201
        assert await asyncio.wait_for(change_event(t), 2) == {
            "type": "messages_changed"
        }
        assert await asyncio.wait_for(change_event(s), 2) == {
            "type": "messages_changed"
        }
        assert (await client.get("/api/messages/3", headers=teacher)).json()[0][
            "text"
        ] == "A live lesson question"
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(change_event(p), 0.25)
    finally:
        await t.close()
        await s.close()
        await p.close()


@pytest.mark.asyncio
async def test_socket_denies_bad_credentials_and_unapproved_origin(client, server):
    with pytest.raises(InvalidStatus):
        async with connect(server, proxy=None, origin="https://untrusted.example"):
            pass
    for frame in [
        json.dumps({"token": "not-a-session"}),
        "[]",
        "{}",
        b"invalid-binary-auth",
    ]:
        async with connect(server, proxy=None) as ws:
            await ws.send(frame)
            with pytest.raises(ConnectionClosed):
                await ws.recv()
            assert ws.close_code == 4401


@pytest.mark.asyncio
async def test_logout_revokes_an_already_open_socket(client, server):
    headers = await auth(client, 3)
    ws = await authenticate(server, headers)
    try:
        assert (
            await client.post("/api/auth/logout", headers=headers)
        ).status_code == 204

        async def wait_closed():
            with pytest.raises(ConnectionClosed):
                while True:
                    await ws.recv()

        await asyncio.wait_for(wait_closed(), 2)
        assert ws.close_code == 4401
    finally:
        await ws.close()
