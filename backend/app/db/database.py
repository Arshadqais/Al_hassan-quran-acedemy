"""Database configuration. Process configuration overrides the private .env file."""

import os
from pathlib import Path
from dotenv import dotenv_values
from sqlalchemy import URL, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

env = {**dotenv_values(Path(__file__).resolve().parents[2] / ".env"), **os.environ}
DATABASE_URL = env.get("DATABASE_URL") or URL.create(
    drivername="postgresql+asyncpg",
    username=env.get("DATABASE_USER", "academy"),
    password=env.get("DATABASE_PASSWORD"),
    host=env.get("DATABASE_HOST", "127.0.0.1"),
    port=int(env.get("DATABASE_PORT", "5432")),
    database=env.get("DATABASE_NAME", "quran_academy"),
)
engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
Session = async_sessionmaker(engine, expire_on_commit=False)


async def check_database():
    async with engine.connect() as connection:
        return (await connection.execute(text("SELECT 1"))).scalar_one() == 1
