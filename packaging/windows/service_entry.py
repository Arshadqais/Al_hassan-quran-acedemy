"""Frozen backend entry point. Only the private desktop launcher invokes helpers."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import sys


def resources():
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2] / "backend"))


def respond(data):
    print(json.dumps(data), flush=True)


async def action(name, payload):
    if name == "create-admin":
        from app.api import UserIn
        from app.models import User
        from app.security import password_hash
        from app.db.database import Session, engine
        from sqlalchemy import select
        try:
            item = UserIn(**payload, role="admin")
            async with Session() as session:
                if await session.scalar(select(User.id).where(User.role == "admin", User.active == True)):
                    raise ValueError("An administrator already exists. Sign in with that account.")
                session.add(User(name=item.name, email=item.email, role="admin", level="Administrator",
                    password_hash=password_hash(item.password)))
                await session.commit()
        finally:
            await engine.dispose()
    elif name == "has-admin":
        from app.models import User
        from app.db.database import Session, engine
        from sqlalchemy import select
        try:
            async with Session() as session:
                exists = await session.scalar(select(User.id).where(User.role == "admin", User.active == True).limit(1))
            return {"ok": True, "exists": exists is not None}
        finally:
            await engine.dispose()
    elif name == "configure-video":
        from app.integrations import verify_video, save_video
        await verify_video(payload["url"], payload["key"], payload["secret"])
        save_video(payload["url"], payload["key"], payload["secret"])
    elif name == "configure-whatsapp":
        from app.integrations import config, ENV_PATH
        from app.whatsapp_setup import verify_whatsapp, save_whatsapp
        values = {**config(), **payload}
        await verify_whatsapp(values)
        save_whatsapp(ENV_PATH, values)
    elif name == "download-quran":
        from app.quran import book
        for edition in ("quran-uthmani", "ur.jalandhry", "en.sahih"):
            await book(edition)
    return {"ok": True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["serve", "migrate", "has-admin", "create-admin", "configure-video", "configure-whatsapp", "download-quran"])
    name = parser.parse_args().action
    if not os.environ.get("ACADEMY_ENV_FILE") or not os.environ.get("ACADEMY_DATA_DIR"):
        respond({"ok": False, "error": "Start the academy from its desktop shortcut."})
        return 1
    try:
        if name == "serve":
            import uvicorn
            from app.main import app
            uvicorn.run(app, host="127.0.0.1", port=18080, ws_max_size=4096, access_log=False)
            return 0
        if name == "migrate":
            from alembic.config import Config
            from alembic import command
            config = Config()
            config.set_main_option("script_location", str(resources() / "alembic").replace("%", "%%"))
            command.upgrade(config, "head")
            respond({"ok": True})
            return 0
        payload = json.loads(sys.stdin.read(16384) or "{}")
        respond(asyncio.run(action(name, payload)))
        return 0
    except Exception as error:
        # Pydantic/provider errors can contain credential inputs. Do not echo them.
        safe = str(error) if isinstance(error, ValueError) and name == "has-admin" else {
            "create-admin": "Could not create administrator. Use a valid email and a 12–128 character password; no existing account is replaced.",
            "configure-video": "Could not verify LiveKit. Check the URL, key, secret, and network.",
            "configure-whatsapp": "Could not verify the WhatsApp sender or approved template. Check credentials and Meta approval.",
            "download-quran": "Could not download all Quran editions. Check the internet connection; existing cached editions were kept.",
            "migrate": "The database upgrade failed. The pre-update backup and existing data were preserved. Contact your developer.",
        }.get(name, "The backend operation failed. Contact your developer.")
        respond({"ok": False, "error": safe})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
