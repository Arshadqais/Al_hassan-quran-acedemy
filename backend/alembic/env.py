import asyncio
from alembic import context
from app.db.database import engine
from app.models import Base


def run(connection):
    context.configure(
        connection=connection, target_metadata=Base.metadata, compare_type=True
    )
    with context.begin_transaction():
        context.run_migrations()


async def online():
    async with engine.connect() as connection:
        await connection.run_sync(run)
    await engine.dispose()


if context.is_offline_mode():
    raise RuntimeError(
        "Use online migrations; credentials are read from the server configuration."
    )
asyncio.run(online())
