import os
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.main import app
from app.security import db, password_hash, _attempts
from app.models import Base, User, Assignment

PASSWORD = "Test-only-password-729!"
HASH = password_hash(PASSWORD)


@pytest_asyncio.fixture
async def client(monkeypatch):
    for key in ("LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"):
        monkeypatch.setenv(key, "")
    url = os.environ.get("ACADEMY_TEST_DATABASE_URL", "sqlite+aiosqlite:///:memory:")
    if not url.endswith("_test") and ":memory:" not in url:
        raise RuntimeError(
            "Test database name must end in _test. Never use academy data."
        )
    engine = create_async_engine(url)
    async with engine.begin() as c:
        await c.run_sync(Base.metadata.drop_all)
        await c.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        for i, role in enumerate(
            ["admin", "teacher", "student", "parent", "student", "teacher"], 1
        ):
            session.add(
                User(
                    name=f"User {i}",
                    email=f"user{i}@example.test",
                    role=role,
                    password_hash=HASH,
                )
            )
        await session.commit()
        session.add_all(
            [
                Assignment(adult_id=2, student_id=3),
                Assignment(adult_id=4, student_id=3),
                Assignment(adult_id=6, student_id=5),
            ]
        )
        await session.commit()

    async def override():
        async with factory() as session:
            yield session

    app.dependency_overrides[db] = override
    _attempts.clear()
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://testserver"
    ) as c:
        c.factory = factory
        yield c
    app.dependency_overrides.clear()
    async with engine.begin() as c:
        await c.run_sync(Base.metadata.drop_all)
    await engine.dispose()


async def auth(client, user):
    response = await client.post(
        "/api/auth/login",
        json={"email": f"user{user}@example.test", "password": PASSWORD},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": "Bearer " + response.json()["token"]}
