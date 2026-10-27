from datetime import timedelta
import pytest
from app.security import token_hash
from app.models import LoginSession, now
from conftest import auth, PASSWORD


@pytest.mark.asyncio
async def test_login_session_expiry_and_logout(client):
    assert (await client.get("/api/users")).status_code == 401
    assert (
        await client.post(
            "/api/auth/login", json={"email": "user1@example.test", "password": "wrong"}
        )
    ).status_code == 401
    headers = await auth(client, 1)
    assert (await client.get("/api/auth/me", headers=headers)).json()["role"] == "admin"
    assert (await client.get("/api/auth/me", headers=headers)).headers[
        "cache-control"
    ] == "no-store"
    assert (await client.post("/api/auth/logout", headers=headers)).status_code == 204
    assert (await client.get("/api/auth/me", headers=headers)).status_code == 401
    headers = await auth(client, 3)
    async with client.factory() as session:
        login = await session.get(
            LoginSession, token_hash(headers["Authorization"][7:])
        )
        login.expires_at = now() - timedelta(seconds=1)
        await session.commit()
    assert (await client.get("/api/auth/me", headers=headers)).status_code == 401


@pytest.mark.asyncio
async def test_login_rate_limit(client):
    for _ in range(10):
        assert (
            await client.post(
                "/api/auth/login",
                json={"email": "missing@example.test", "password": "bad"},
            )
        ).status_code == 401
    assert (
        await client.post(
            "/api/auth/login",
            json={"email": "user1@example.test", "password": PASSWORD},
        )
    ).status_code == 429


@pytest.mark.asyncio
async def test_account_creation_and_assignment_are_admin_only(client):
    admin = await auth(client, 1)
    student = await auth(client, 3)
    data = {
        "name": "New learner",
        "email": "NEW@example.test",
        "password": PASSWORD,
        "role": "student",
    }
    assert (
        await client.post("/api/users", json=data, headers=student)
    ).status_code == 403
    r = await client.post("/api/users", json=data, headers=admin)
    assert r.status_code == 201 and r.json()["email"] == "new@example.test"
    assert "password_hash" not in r.json()
    assert (
        await client.post("/api/users", json=data, headers=admin)
    ).status_code == 409
    assert (
        await client.post(
            "/api/assignments",
            json={"adult_id": 4, "student_id": r.json()["id"]},
            headers=admin,
        )
    ).status_code == 201
    assert (
        await client.post(
            "/api/assignments", json={"adult_id": 3, "student_id": 5}, headers=admin
        )
    ).status_code == 422


@pytest.mark.asyncio
async def test_student_parent_and_teacher_record_ownership(client):
    teacher = await auth(client, 2)
    student = await auth(client, 3)
    parent = await auth(client, 4)
    progress = {"surah": "Al-Fatiha", "percent": 65, "notes": "Practice pronunciation"}
    assert (
        await client.put("/api/students/3/progress", json=progress, headers=teacher)
    ).status_code == 200
    for headers in (student, parent, teacher):
        r = await client.get("/api/students/3/progress", headers=headers)
        assert r.status_code == 200 and r.json()[0]["percent"] == 65
        assert (
            await client.get("/api/students/5/progress", headers=headers)
        ).status_code == 404
    assert (
        await client.put("/api/students/3/progress", json=progress, headers=parent)
    ).status_code == 403
    assert (
        await client.put(
            "/api/students/3/progress",
            json={**progress, "percent": 101},
            headers=teacher,
        )
    ).status_code == 422
    assert {
        u["id"] for u in (await client.get("/api/users", headers=parent)).json()
    } == {3, 4}


async def schedule(client, headers):
    data = {
        "title": "Recitation",
        "teacher_id": 2,
        "student_ids": [3],
        "starts_at": "2026-11-01T09:00:00+05:00",
        "duration": 30,
    }
    r = await client.post("/api/classes", json=data, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]


@pytest.mark.asyncio
async def test_schedule_attendance_and_private_video_access(client):
    teacher = await auth(client, 2)
    student = await auth(client, 3)
    other = await auth(client, 5)
    parent = await auth(client, 4)
    session_id = await schedule(client, teacher)
    assert len((await client.get("/api/classes", headers=student)).json()) == 1
    assert (await client.get("/api/classes", headers=other)).json() == []
    assert (
        await client.put(
            f"/api/classes/{session_id}/attendance",
            json={"student_id": 3, "present": True},
            headers=teacher,
        )
    ).status_code == 200
    assert (await client.get("/api/attendance", headers=parent)).json()[0][
        "present"
    ] is True
    assert (await client.get("/api/attendance", headers=other)).json() == []
    assert (
        await client.put(
            f"/api/classes/{session_id}/attendance",
            json={"student_id": 5, "present": True},
            headers=teacher,
        )
    ).status_code == 404
    assert (
        await client.post(f"/api/classes/{session_id}/room-token", headers=other)
    ).status_code == 404
    assert (
        await client.post(f"/api/classes/{session_id}/room-token", headers=student)
    ).status_code == 503
    assert (
        await client.post(f"/api/classes/{session_id}/room-token", headers=parent)
    ).status_code == 403
    assert (
        await client.post(
            "/api/classes",
            json={
                "title": "Bad",
                "teacher_id": 2,
                "student_ids": [5],
                "starts_at": "2026-11-01T09:00:00Z",
            },
            headers=teacher,
        )
    ).status_code == 404


@pytest.mark.asyncio
async def test_homework_and_resources_are_scoped_and_persisted(client):
    teacher = await auth(client, 2)
    student = await auth(client, 3)
    other = await auth(client, 5)
    r = await client.post(
        "/api/homework",
        json={"student_id": 3, "title": "Revise Al-Fatiha"},
        headers=teacher,
    )
    assert r.status_code == 201
    assert (
        await client.put(
            f"/api/homework/{r.json()['id']}", json={"completed": True}, headers=other
        )
    ).status_code == 404
    assert (
        await client.put(
            f"/api/homework/{r.json()['id']}", json={"completed": True}, headers=student
        )
    ).json()["completed"] is True
    assert (await client.get("/api/homework", headers=teacher)).json()[0][
        "completed"
    ] is True
    assert (
        await client.post(
            "/api/resources",
            json={"student_id": 3, "title": "Tajweed", "content": "Practice slowly."},
            headers=teacher,
        )
    ).status_code == 201
    assert (await client.get("/api/resources", headers=student)).json()[0][
        "content"
    ] == "Practice slowly."
    assert (await client.get("/api/resources", headers=other)).json() == []


@pytest.mark.asyncio
async def test_private_conversations_cannot_be_read_by_other_roles(client):
    teacher = await auth(client, 2)
    student = await auth(client, 3)
    parent = await auth(client, 4)
    admin = await auth(client, 1)
    other = await auth(client, 5)
    assert (
        await client.post(
            "/api/messages",
            json={"recipient_id": 2, "text": "My lesson question"},
            headers=student,
        )
    ).status_code == 201
    assert (await client.get("/api/messages/3", headers=teacher)).json()[0][
        "text"
    ] == "My lesson question"
    assert (await client.get("/api/messages/2", headers=parent)).json() == []
    assert (await client.get("/api/messages/2", headers=admin)).json() == []
    assert (await client.get("/api/messages/2", headers=other)).status_code == 404
    assert (
        await client.post(
            "/api/messages", json={"recipient_id": 2, "text": "Hello"}, headers=other
        )
    ).status_code == 404
    assert (
        await client.post(
            "/api/messages", json={"recipient_id": 2, "text": "   "}, headers=student
        )
    ).status_code == 422


@pytest.mark.asyncio
async def test_parent_feedback_and_admin_report_permissions(client):
    parent = await auth(client, 4)
    student = await auth(client, 3)
    admin = await auth(client, 1)
    assert (
        await client.post(
            "/api/feedback",
            json={"student_id": 3, "rating": 5, "text": "Good progress"},
            headers=parent,
        )
    ).status_code == 201
    assert (
        await client.post(
            "/api/feedback",
            json={"student_id": 5, "rating": 5, "text": "Not my child"},
            headers=parent,
        )
    ).status_code == 404
    assert (await client.get("/api/admin/reports", headers=student)).status_code == 403
    report = (await client.get("/api/admin/reports", headers=admin)).json()
    assert report["students"] == 2 and report["feedback"][0]["text"] == "Good progress"


@pytest.mark.asyncio
async def test_classroom_tokens_are_short_lived_scoped_and_teacher_led(
    client, monkeypatch
):
    import jwt
    from app.models import ClassSession

    teacher = await auth(client, 2)
    student = await auth(client, 3)
    other = await auth(client, 5)
    session_id = await schedule(client, teacher)
    monkeypatch.setenv("LIVEKIT_URL", "wss://classroom.example.test")
    monkeypatch.setenv("LIVEKIT_API_KEY", "test-only-key")
    monkeypatch.setenv(
        "LIVEKIT_API_SECRET", "test-only-secret-that-is-at-least-32-bytes-long"
    )
    # Only an enrolled student/teacher can enter, and only during the lesson window.
    assert (
        await client.post(f"/api/classes/{session_id}/room-token", headers=other)
    ).status_code == 404
    async with client.factory() as session:
        item = await session.get(ClassSession, session_id)
        item.starts_at = now()
        await session.commit()
    for headers, is_teacher in ((teacher, True), (student, False)):
        response = await client.post(
            f"/api/classes/{session_id}/room-token", headers=headers
        )
        assert response.status_code == 200, response.text
        claims = jwt.decode(
            response.json()["token"],
            "test-only-secret-that-is-at-least-32-bytes-long",
            algorithms=["HS256"],
            issuer="test-only-key",
        )
        assert claims["video"]["room"] == f"academy-class-{session_id}"
        assert claims["video"]["roomJoin"] is True
        assert ("screen_share" in claims["video"]["canPublishSources"]) is is_teacher
        assert claims["exp"] - claims["nbf"] <= 600
    async with client.factory() as session:
        item = await session.get(ClassSession, session_id)
        item.starts_at = now() + timedelta(days=1)
        await session.commit()
    assert (
        await client.post(f"/api/classes/{session_id}/room-token", headers=student)
    ).status_code == 403


@pytest.mark.asyncio
async def test_password_changes_revoke_sessions_and_do_not_echo_credentials(client):
    headers = await auth(client, 3)
    invalid = await client.post(
        "/api/auth/password",
        json={"current_password": PASSWORD, "new_password": "short"},
        headers=headers,
    )
    assert (
        invalid.status_code == 422
        and "short" not in invalid.text
        and PASSWORD not in invalid.text
    )
    wrong = await client.post(
        "/api/auth/password",
        json={"current_password": "wrong", "new_password": "New-test-password-831!"},
        headers=headers,
    )
    assert wrong.status_code == 400
    changed = await client.post(
        "/api/auth/password",
        json={"current_password": PASSWORD, "new_password": "New-test-password-831!"},
        headers=headers,
    )
    assert changed.status_code == 204
    assert (await client.get("/api/auth/me", headers=headers)).status_code == 401
    assert (
        await client.post(
            "/api/auth/login",
            json={"email": "user3@example.test", "password": PASSWORD},
        )
    ).status_code == 401
    assert (
        await client.post(
            "/api/auth/login",
            json={"email": "user3@example.test", "password": "New-test-password-831!"},
        )
    ).status_code == 200
