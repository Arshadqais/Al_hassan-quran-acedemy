"""Run locally: python -m app.manage init-db | create-admin. Never seeds passwords."""

import asyncio
import getpass
import sys
from sqlalchemy import select
from app.db.database import engine, Session
from app.models import User
from app.security import password_hash
from app.api import UserIn


async def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "init-db":
        import subprocess

        subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], check=True)
    elif command == "create-admin":
        name = input("Admin name: ").strip()
        email = input("Admin email: ").strip().lower()
        password = getpass.getpass("Password (12+ characters): ")
        if password != getpass.getpass("Confirm password: "):
            raise SystemExit("Passwords do not match.")
        try:
            data = UserIn(name=name, email=email, password=password, role="admin")
        except ValueError:
            raise SystemExit(
                "Invalid details. Use a name, valid email, and password of 12–128 characters."
            ) from None
        async with Session() as session:
            if await session.scalar(select(User.id).where(User.email == data.email)):
                raise SystemExit("Email already exists. No account was changed.")
            session.add(
                User(
                    name=data.name,
                    email=data.email,
                    role="admin",
                    password_hash=password_hash(data.password),
                )
            )
            await session.commit()
        print("Administrator created. No password was written to logs.")
    else:
        raise SystemExit("Usage: python -m app.manage init-db | create-admin")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
