"""Local secure configuration and checks; no passwords/tokens are printed."""

import argparse
import asyncio
import getpass
import os
from pathlib import Path
import ssl
from urllib.parse import urlparse

import aiohttp
from dotenv import dotenv_values, set_key
from livekit import api

ENV_PATH = Path(__file__).resolve().parents[1] / ".env"


def config():
    return {**dotenv_values(ENV_PATH), **os.environ}


async def verify_video(url, key, secret):
    parsed = urlparse(url)
    if (
        parsed.scheme != "wss"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Use the wss:// server URL from your LiveKit project.")
    if not key or not secret:
        raise ValueError("LiveKit API key and secret are required.")
    context = ssl.create_default_context()
    async with aiohttp.ClientSession(
        trust_env=True,
        timeout=aiohttp.ClientTimeout(total=15),
        connector=aiohttp.TCPConnector(ssl=context),
    ) as session:
        client = api.LiveKitAPI(
            url=url, api_key=key, api_secret=secret, session=session
        )
        await client.room.list_rooms(api.ListRoomsRequest())


def save_video(url, key, secret):
    if not ENV_PATH.exists():
        raise ValueError("Run the local setup command first.")
    for value in (url, key, secret):
        if any(c in value for c in ("\n", "\r", "\x00")):
            raise ValueError("Configuration entries must each be a single line.")
    ENV_PATH.chmod(0o600)
    for name, value in [
        ("LIVEKIT_URL", url),
        ("LIVEKIT_API_KEY", key),
        ("LIVEKIT_API_SECRET", secret),
    ]:
        set_key(str(ENV_PATH), name, value)


async def main(command):
    if command == "has-admin":
        from sqlalchemy import select
        from app.db.database import Session, engine
        from app.models import User

        async with Session() as session:
            exists = await session.scalar(
                select(User.id)
                .where(User.role == "admin", User.active == True)
                .limit(1)
            )
        await engine.dispose()
        raise SystemExit(0 if exists else 10)
    elif command == "configure-video":
        values = config()
        url = input("LiveKit WSS project URL: ").strip() or values.get(
            "LIVEKIT_URL", ""
        )
        key = getpass.getpass(
            "LiveKit API key (hidden; blank keeps existing): "
        ).strip() or values.get("LIVEKIT_API_KEY", "")
        secret = getpass.getpass(
            "LiveKit API secret (hidden; blank keeps existing): "
        ).strip() or values.get("LIVEKIT_API_SECRET", "")
        try:
            await verify_video(url, key, secret)
        except ValueError as error:
            raise SystemExit(str(error)) from None
        except Exception:
            raise SystemExit(
                "Could not authenticate with LiveKit. Check the project URL, key, secret, network and TLS trust. Existing settings were not changed."
            ) from None
        save_video(url, key, secret)
        print(
            "LiveKit authentication passed. Configuration saved privately. Restart the academy API before joining a class."
        )
    elif command == "download-quran":
        from app.quran import book

        missing = []
        for edition in ("quran-uthmani", "ur.jalandhry", "en.sahih"):
            try:
                result = await book(edition)
                print(
                    f"Cached {edition}: {len(result['verses'])} ayahs across all 30 paras."
                )
            except Exception:
                missing.append(edition)
                print(f"Could not download/validate {edition}.")
        if missing:
            raise SystemExit(
                "Missing editions: "
                + ", ".join(missing)
                + ". Check access to api.alquran.cloud; valid cached editions are retained."
            )
    elif command == "check-services":
        from app.db.database import check_database, engine
        from app.quran import CACHE_DIR

        try:
            print(
                "PostgreSQL: "
                + ("connected" if await check_database() else "not connected")
            )
        except Exception:
            print("PostgreSQL: unavailable; check Docker Desktop and backend/.env")
        finally:
            await engine.dispose()
        print(
            "Quran Arabic local cache: "
            + (
                "available"
                if (CACHE_DIR / "quran-uthmani.json").exists()
                else "not downloaded; run download-quran"
            )
        )
        values = config()
        try:
            await verify_video(
                values.get("LIVEKIT_URL", ""),
                values.get("LIVEKIT_API_KEY", ""),
                values.get("LIVEKIT_API_SECRET", ""),
            )
            print("Internet video provider: authenticated")
        except ValueError:
            print("Internet video provider: not configured; run configure-video")
        except Exception:
            print(
                "Internet video provider: configured but authentication/network check failed"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=["configure-video", "download-quran", "check-services", "has-admin"],
    )
    args = parser.parse_args()
    asyncio.run(main(args.command))
