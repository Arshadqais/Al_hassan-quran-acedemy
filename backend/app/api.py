"""Authenticated pilot APIs. Parents and teachers are scoped to linked students."""

from datetime import datetime, timezone, timedelta
import os
from urllib.parse import urlparse
from livekit import api as livekit_api
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select, or_, and_, delete, func
from sqlalchemy.exc import IntegrityError
from starlette.concurrency import run_in_threadpool
from app.db.database import env
from app.models import (
    now,
    User,
    Assignment,
    ClassSession,
    Enrollment,
    Attendance,
    Progress,
    Homework,
    Resource,
    Message,
    Feedback,
    AuditLog,
    LoginSession,
)
from app.security import (
    db,
    current_user,
    bearer,
    token_hash,
    password_hash,
    verify_password,
    issue_session,
    public_user,
    login_limit,
    _dummy,
)

router = APIRouter(prefix="/api")


class LoginIn(BaseModel):
    email: str = Field(min_length=3, max_length=160)
    password: str = Field(min_length=1, max_length=128)


class UserIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: str = Field(
        min_length=3, max_length=160, pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$"
    )
    password: str = Field(min_length=12, max_length=128)
    role: Literal["admin", "teacher", "student", "parent"]
    level: str = Field(default="Level 1", max_length=80)

    @field_validator("email")
    @classmethod
    def normalized_email(cls, v):
        return v.strip().lower()

    @field_validator("name")
    @classmethod
    def nonblank_name(cls, v):
        if not v.strip():
            raise ValueError("Name cannot be blank")
        return v.strip()


class LinkIn(BaseModel):
    adult_id: int
    student_id: int


class ClassIn(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    teacher_id: int
    student_ids: list[int] = Field(min_length=1, max_length=100)
    starts_at: datetime
    duration: int = Field(default=30, ge=10, le=180)
    category: Literal["Individual", "Group"] = "Individual"

    @field_validator("starts_at")
    @classmethod
    def timezone_required(cls, v):
        if v.tzinfo is None:
            raise ValueError("Include a timezone offset")
        return v.astimezone(timezone.utc).replace(tzinfo=None)


class AttendanceIn(BaseModel):
    student_id: int
    present: bool


class ProgressIn(BaseModel):
    surah: str = Field(min_length=1, max_length=80)
    percent: int = Field(ge=0, le=100)
    notes: str = Field(default="", max_length=1000)


class HomeworkIn(BaseModel):
    student_id: int
    title: str = Field(min_length=1, max_length=160)


class CompletionIn(BaseModel):
    completed: bool


class ResourceIn(BaseModel):
    student_id: int
    title: str = Field(min_length=1, max_length=160)
    content: str = Field(min_length=1, max_length=20000)


class MessageIn(BaseModel):
    recipient_id: int
    text: str = Field(min_length=1, max_length=2000)

    @field_validator("text")
    @classmethod
    def nonblank(cls, v):
        if not v.strip():
            raise ValueError("Message cannot be blank")
        return v.strip()


class FeedbackIn(BaseModel):
    student_id: int
    rating: int = Field(ge=1, le=5)
    text: str = Field(min_length=1, max_length=1500)


def require(user, *roles):
    if user.role not in roles:
        raise HTTPException(403, "Not permitted for this role")


async def scoped_students(session, user):
    if user.role == "admin":
        return list(
            (await session.scalars(select(User.id).where(User.role == "student"))).all()
        )
    if user.role == "student":
        return [user.id]
    return list(
        (
            await session.scalars(
                select(Assignment.student_id).where(Assignment.adult_id == user.id)
            )
        ).all()
    )


async def check_student(session, user, student_id, write=False):
    if write:
        require(user, "admin", "teacher")
    if student_id not in await scoped_students(session, user):
        raise HTTPException(404, "Student not found")
    return await session.get(User, student_id)


async def session_access(session, user, session_id, write=False):
    item = await session.get(ClassSession, session_id)
    if not item:
        raise HTTPException(404, "Class not found")
    if user.role == "admin":
        return item
    if user.role == "teacher" and item.teacher_id == user.id:
        return item
    if not write and user.role in ("student", "parent"):
        ids = await scoped_students(session, user)
        enrolled = await session.scalar(
            select(Enrollment.id).where(
                Enrollment.session_id == session_id, Enrollment.student_id.in_(ids)
            )
        )
        if enrolled:
            return item
    raise HTTPException(404, "Class not found")


def audit(session, user, action):
    session.add(AuditLog(actor_id=user.id, action=action))


def serialize(item, fields):
    return {field: getattr(item, field) for field in fields.split()}


@router.post("/auth/login")
async def login(data: LoginIn, request: Request, session=Depends(db)):
    login_limit(request)
    user = await session.scalar(
        select(User).where(User.email == data.email.strip().lower())
    )
    valid = await run_in_threadpool(
        verify_password, data.password, user.password_hash if user else _dummy
    )
    if not valid or not user or not user.active:
        raise HTTPException(401, "Email or password is incorrect")
    token = await issue_session(session, user)
    return {"token": token, "user": public_user(user), "expires_in": 28800}


@router.get("/auth/me")
async def me(user=Depends(current_user)):
    return public_user(user)


@router.post("/auth/logout", status_code=204)
async def logout(
    credentials=Depends(bearer), user=Depends(current_user), session=Depends(db)
):
    await session.execute(
        delete(LoginSession).where(
            LoginSession.token_hash == token_hash(credentials.credentials)
        )
    )
    await session.commit()


@router.get("/users")
async def users(user=Depends(current_user), session=Depends(db)):
    if user.role == "admin":
        rows = (await session.scalars(select(User).order_by(User.name))).all()
    else:
        students = await scoped_students(session, user)
        # Teachers and parents see only their linked learner profiles and themselves.
        rows = (
            await session.scalars(
                select(User)
                .where(User.id.in_([user.id, *students]))
                .order_by(User.name)
            )
        ).all()
    return [public_user(r) for r in rows]


@router.post("/users", status_code=201)
async def create_user(data: UserIn, user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    item = User(
        **data.model_dump(exclude={"password"}),
        password_hash=await run_in_threadpool(password_hash, data.password),
    )
    session.add(item)
    audit(session, user, "create user")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "Email already registered")
    return public_user(item)


@router.post("/assignments", status_code=201)
async def link(data: LinkIn, user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    adult = await session.get(User, data.adult_id)
    student = await session.get(User, data.student_id)
    if (
        not adult
        or adult.role not in ("parent", "teacher")
        or not student
        or student.role != "student"
    ):
        raise HTTPException(422, "Link a teacher or parent to a student")
    session.add(Assignment(**data.model_dump()))
    audit(session, user, "link adult to student")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "Assignment already exists")
    return {"linked": True}


@router.get("/classes")
async def classes(user=Depends(current_user), session=Depends(db)):
    query = select(ClassSession).order_by(ClassSession.starts_at)
    if user.role == "teacher":
        query = query.where(ClassSession.teacher_id == user.id)
    elif user.role != "admin":
        query = query.where(
            ClassSession.id.in_(
                select(Enrollment.session_id).where(
                    Enrollment.student_id.in_(await scoped_students(session, user))
                )
            )
        )
    rows = (await session.scalars(query)).all()
    result = []
    for row in rows:
        teacher = await session.get(User, row.teacher_id)
        result.append(
            {
                **serialize(row, "id title teacher_id starts_at duration category"),
                "teacher": teacher.name,
            }
        )
    return result


@router.post("/classes", status_code=201)
async def create_class(data: ClassIn, user=Depends(current_user), session=Depends(db)):
    require(user, "admin", "teacher")
    if user.role == "teacher" and data.teacher_id != user.id:
        raise HTTPException(403, "Cannot schedule for another teacher")
    teacher = await session.get(User, data.teacher_id)
    if not teacher or teacher.role != "teacher":
        raise HTTPException(422, "Select a teacher")
    ids = list(set(data.student_ids))
    if data.category == "Individual" and len(ids) != 1:
        raise HTTPException(422, "Individual classes have one student")
    for student_id in ids:
        await check_student(session, user, student_id, write=True)
        if user.role == "admin" and not await session.scalar(
            select(Assignment.id).where(
                Assignment.adult_id == teacher.id, Assignment.student_id == student_id
            )
        ):
            raise HTTPException(422, "Assign the student to this teacher first")
    item = ClassSession(**data.model_dump(exclude={"student_ids"}))
    session.add(item)
    await session.flush()
    for student_id in ids:
        session.add(Enrollment(session_id=item.id, student_id=student_id))
    audit(session, user, "schedule class")
    await session.commit()
    return serialize(item, "id title teacher_id starts_at duration category")


@router.get("/attendance")
async def attendance(user=Depends(current_user), session=Depends(db)):
    ids = await scoped_students(session, user)
    query = select(Attendance).where(Attendance.student_id.in_(ids))
    if user.role == "teacher":
        query = query.where(
            Attendance.session_id.in_(
                select(ClassSession.id).where(ClassSession.teacher_id == user.id)
            )
        )
    return [
        serialize(r, "id session_id student_id present")
        for r in (await session.scalars(query)).all()
    ]


@router.put("/classes/{session_id}/attendance")
async def mark_attendance(
    session_id: int, data: AttendanceIn, user=Depends(current_user), session=Depends(db)
):
    require(user, "admin", "teacher")
    await session_access(session, user, session_id, write=True)
    if not await session.scalar(
        select(Enrollment.id).where(
            Enrollment.session_id == session_id,
            Enrollment.student_id == data.student_id,
        )
    ):
        raise HTTPException(404, "Student not enrolled in this class")
    item = await session.scalar(
        select(Attendance).where(
            Attendance.session_id == session_id,
            Attendance.student_id == data.student_id,
        )
    )
    if item:
        item.present = data.present
    else:
        session.add(Attendance(session_id=session_id, **data.model_dump()))
    audit(session, user, "mark attendance")
    await session.commit()
    return {"saved": True}


@router.get("/students/{student_id}/progress")
async def progress(student_id: int, user=Depends(current_user), session=Depends(db)):
    await check_student(session, user, student_id)
    return [
        serialize(r, "id student_id surah percent notes")
        for r in (
            await session.scalars(
                select(Progress).where(Progress.student_id == student_id)
            )
        ).all()
    ]


@router.put("/students/{student_id}/progress")
async def save_progress(
    student_id: int, data: ProgressIn, user=Depends(current_user), session=Depends(db)
):
    await check_student(session, user, student_id, write=True)
    item = await session.scalar(
        select(Progress).where(
            Progress.student_id == student_id, Progress.surah == data.surah
        )
    )
    if item:
        item.percent = data.percent
        item.notes = data.notes
    else:
        item = Progress(student_id=student_id, **data.model_dump())
        session.add(item)
    audit(session, user, "update progress")
    await session.commit()
    return serialize(item, "id student_id surah percent notes")


@router.get("/homework")
async def homework(user=Depends(current_user), session=Depends(db)):
    query = select(Homework).where(
        Homework.student_id.in_(await scoped_students(session, user))
    )
    if user.role == "teacher":
        query = query.where(Homework.teacher_id == user.id)
    return [
        serialize(r, "id student_id teacher_id title completed")
        for r in (await session.scalars(query)).all()
    ]


@router.post("/homework", status_code=201)
async def assign_homework(
    data: HomeworkIn, user=Depends(current_user), session=Depends(db)
):
    await check_student(session, user, data.student_id, write=True)
    item = Homework(teacher_id=user.id, **data.model_dump())
    session.add(item)
    audit(session, user, "assign homework")
    await session.commit()
    return serialize(item, "id student_id teacher_id title completed")


@router.put("/homework/{homework_id}")
async def complete_homework(
    homework_id: int,
    data: CompletionIn,
    user=Depends(current_user),
    session=Depends(db),
):
    require(user, "student")
    item = await session.get(Homework, homework_id)
    if not item or item.student_id != user.id:
        raise HTTPException(404, "Homework not found")
    item.completed = data.completed
    await session.commit()
    return serialize(item, "id student_id teacher_id title completed")


@router.get("/resources")
async def resources(user=Depends(current_user), session=Depends(db)):
    query = select(Resource).where(
        Resource.student_id.in_(await scoped_students(session, user))
    )
    if user.role == "teacher":
        query = query.where(Resource.teacher_id == user.id)
    return [
        serialize(r, "id student_id teacher_id title content")
        for r in (await session.scalars(query)).all()
    ]


@router.post("/resources", status_code=201)
async def add_resource(
    data: ResourceIn, user=Depends(current_user), session=Depends(db)
):
    await check_student(session, user, data.student_id, write=True)
    item = Resource(teacher_id=user.id, **data.model_dump())
    session.add(item)
    audit(session, user, "assign resource")
    await session.commit()
    return serialize(item, "id student_id teacher_id title content")


async def can_message(session, user, other):
    if not other or not other.active or other.id == user.id:
        return False
    if user.role == "admin" or other.role == "admin":
        return True
    if user.role == "teacher" and other.role in ("student", "parent"):
        mine = set(await scoped_students(session, user))
        theirs = set(await scoped_students(session, other))
        return bool(mine & theirs)
    if other.role == "teacher" and user.role in ("student", "parent"):
        return await can_message(session, other, user)
    return False


@router.get("/contacts")
async def contacts(user=Depends(current_user), session=Depends(db)):
    rows = (await session.scalars(select(User).where(User.active == True))).all()
    return [public_user(r) for r in rows if await can_message(session, user, r)]


@router.get("/messages/{other_id}")
async def conversation(other_id: int, user=Depends(current_user), session=Depends(db)):
    other = await session.get(User, other_id)
    if not await can_message(session, user, other):
        raise HTTPException(404, "Conversation not found")
    # No administrator/parent access to somebody else's private conversation.
    query = (
        select(Message)
        .where(
            or_(
                and_(Message.sender_id == user.id, Message.recipient_id == other_id),
                and_(Message.sender_id == other_id, Message.recipient_id == user.id),
            )
        )
        .order_by(Message.created_at.desc(), Message.id.desc())
        .limit(100)
    )
    return [
        serialize(r, "id sender_id recipient_id text created_at")
        for r in reversed((await session.scalars(query)).all())
    ]


@router.post("/messages", status_code=201)
async def send_message(
    data: MessageIn, user=Depends(current_user), session=Depends(db)
):
    other = await session.get(User, data.recipient_id)
    if not await can_message(session, user, other):
        raise HTTPException(404, "Recipient not found")
    item = Message(sender_id=user.id, **data.model_dump())
    session.add(item)
    await session.commit()
    return serialize(item, "id sender_id recipient_id text created_at")


@router.post("/feedback", status_code=201)
async def feedback(data: FeedbackIn, user=Depends(current_user), session=Depends(db)):
    require(user, "parent")
    await check_student(session, user, data.student_id)
    session.add(Feedback(parent_id=user.id, **data.model_dump()))
    await session.commit()
    return {"saved": True}


@router.get("/admin/reports")
async def reports(user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    result = {}
    for role in ("student", "teacher", "parent"):
        result[role + "s"] = await session.scalar(
            select(func.count()).select_from(User).where(User.role == role)
        )
    result["classes"] = await session.scalar(
        select(func.count()).select_from(ClassSession)
    )
    result["feedback"] = [
        serialize(r, "id parent_id student_id rating text")
        for r in (
            await session.scalars(
                select(Feedback).order_by(Feedback.id.desc()).limit(100)
            )
        ).all()
    ]
    result["audit"] = [
        serialize(r, "id actor_id action created_at")
        for r in (
            await session.scalars(
                select(AuditLog).order_by(AuditLog.id.desc()).limit(100)
            )
        ).all()
    ]
    return result


@router.post("/classes/{session_id}/room-token")
async def room_token(session_id: int, user=Depends(current_user), session=Depends(db)):
    require(user, "admin", "teacher", "student")
    item = await session_access(session, user, session_id)
    url = os.environ.get("LIVEKIT_URL", env.get("LIVEKIT_URL", ""))
    key = os.environ.get("LIVEKIT_API_KEY", env.get("LIVEKIT_API_KEY", ""))
    secret = os.environ.get("LIVEKIT_API_SECRET", env.get("LIVEKIT_API_SECRET", ""))
    parsed = urlparse(url)
    if (
        not key
        or not secret
        or parsed.scheme != "wss"
        or not parsed.hostname
        or parsed.username
    ):
        raise HTTPException(
            503, "Private video provider is not configured. No room has been created."
        )
    current = now()
    if current < item.starts_at - timedelta(
        minutes=15
    ) or current > item.starts_at + timedelta(minutes=item.duration + 30):
        raise HTTPException(
            403,
            "Classroom opens 15 minutes before the lesson and closes 30 minutes after it ends.",
        )
    sources = ["camera", "microphone"]
    if user.role in ("admin", "teacher"):
        sources += ["screen_share", "screen_share_audio"]
    token = (
        livekit_api.AccessToken(key, secret)
        .with_identity(f"academy-user-{user.id}")
        .with_name(user.name)
        .with_ttl(timedelta(minutes=10))
        .with_grants(
            livekit_api.VideoGrants(
                room_join=True,
                room=f"academy-class-{item.id}",
                can_publish=True,
                can_subscribe=True,
                can_publish_data=False,
                can_publish_sources=sources,
            )
        )
        .to_jwt()
    )
    audit(session, user, "join private classroom")
    await session.commit()
    return {"url": url, "token": token, "expires_in": 600}


class PasswordChangeIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)


@router.post("/auth/password", status_code=204)
async def change_password(
    data: PasswordChangeIn,
    request: Request,
    user=Depends(current_user),
    session=Depends(db),
):
    login_limit(request)
    if not await run_in_threadpool(
        verify_password, data.current_password, user.password_hash
    ):
        raise HTTPException(400, "Current password is incorrect")
    user.password_hash = await run_in_threadpool(password_hash, data.new_password)
    await session.execute(delete(LoginSession).where(LoginSession.user_id == user.id))
    audit(session, user, "change own password and revoke sessions")
    await session.commit()
