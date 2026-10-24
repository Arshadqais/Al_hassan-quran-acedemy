from pathlib import Path

from dotenv import dotenv_values
from sqlalchemy import URL, text
from sqlalchemy.ext.asyncio import create_async_engine

env = dotenv_values(Path(__file__).resolve().parents[2] / ".env")

DATABASE_URL = URL.create(
    drivername="postgresql+asyncpg",
    username=env["DATABASE_USER"],
    password=env["DATABASE_PASSWORD"],
    host=env["DATABASE_HOST"],
    port=int(env["DATABASE_PORT"]),
    database=env["DATABASE_NAME"],
)

engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)


async def check_database():
    async with engine.connect() as connection:
        result = await connection.execute(text("SELECT 1"))
        return result.scalar_one() == 1
