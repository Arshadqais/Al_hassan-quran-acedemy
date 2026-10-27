"""Recurring schedules, student summaries, and explicit administrator chat review."""
from datetime import datetime, date, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select, or_, and_, case, func
from app.models import (ClassSchedule, ScheduleEnrollment, ClassSession, Enrollment,
    Attendance, Progress, Homework, Resource, User, Assignment, Message, now)
from app.api import (require, scoped_students, check_student, audit, serialize, public_user)
from app.security import db, current_user
from app.recurrence import expand_schedules

router = APIRouter(prefix="/api")


class ScheduleIn(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    teacher_id: int
    student_ids: list[int] = Field(min_length=1, max_length=100)
    start_date: date
    end_date: date | None = None
    local_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    timezone: str = Field(default="Asia/Karachi", max_length=80)
    weekdays: list[int] = Field(min_length=1, max_length=7)
    duration: int = Field(default=30, ge=10, le=180)
    category: Literal["Individual", "Group"] = "Individual"

    @field_validator("timezone")
    @classmethod
    def valid_zone(cls, value):
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Choose an IANA timezone")
        return value

    @field_validator("weekdays")
    @classmethod
    def valid_days(cls, values):
        if any(v < 0 or v > 6 for v in values):
            raise ValueError("Weekdays use Monday=0 through Sunday=6")
        return sorted(set(values))

    @model_validator(mode="after")
    def dates(self):
        if self.end_date and self.end_date < self.start_date:
            raise ValueError("End date must follow start date")
        if self.start_date > date.today() + timedelta(days=366):
            raise ValueError("Choose a start date within the next year")
        return self


@router.post("/schedules", status_code=201)
async def create_schedule(data: ScheduleIn, user=Depends(current_user), session=Depends(db)):
    require(user, "admin", "teacher")
    if user.role == "teacher" and data.teacher_id != user.id:
        raise HTTPException(403, "Cannot schedule for another teacher")
    teacher = await session.get(User, data.teacher_id)
    if not teacher or teacher.role != "teacher" or not teacher.active:
        raise HTTPException(422, "Select an active teacher")
    ids = sorted(set(data.student_ids))
    if data.category == "Individual" and len(ids) != 1:
        raise HTTPException(422, "Individual schedules have one student")
    for student_id in ids:
        learner = await check_student(session, user, student_id, write=True)
        if not learner or learner.role != "student" or not learner.active:
            raise HTTPException(422, "Select an active student")
        if not await session.scalar(select(Assignment.id).where(
            Assignment.adult_id == teacher.id, Assignment.student_id == student_id)):
            raise HTTPException(422, "Assign the student to this teacher first")
    rule = ClassSchedule(**data.model_dump(exclude={"student_ids", "weekdays"}),
        weekdays=",".join(map(str, data.weekdays)))
    session.add(rule)
    await session.flush()
    session.add_all(ScheduleEnrollment(schedule_id=rule.id, student_id=s) for s in ids)
    audit(session, user, "create recurring schedule")
    await session.commit()
    await expand_schedules(session, user)
    return {"id": rule.id, "saved": True}


@router.get("/schedules")
async def schedules(user=Depends(current_user), session=Depends(db)):
    query = select(ClassSchedule).order_by(ClassSchedule.id.desc())
    if user.role == "teacher":
        query = query.where(ClassSchedule.teacher_id == user.id)
    elif user.role != "admin":
        query = query.where(ClassSchedule.id.in_(select(ScheduleEnrollment.schedule_id).where(
            ScheduleEnrollment.student_id.in_(await scoped_students(session, user)))))
    result = []
    for r in (await session.scalars(query)).all():
        teacher = await session.get(User, r.teacher_id)
        ids = (await session.scalars(select(ScheduleEnrollment.student_id).where(
            ScheduleEnrollment.schedule_id == r.id))).all()
        # Parent/student clients only receive their authorized learner IDs.
        if user.role not in ("admin", "teacher"):
            allowed = await scoped_students(session, user)
            ids = [i for i in ids if i in allowed]
        result.append({**serialize(r, "id title teacher_id start_date end_date local_time timezone duration category active"),
            "weekdays": [int(v) for v in r.weekdays.split(",")], "student_ids": list(ids), "teacher": teacher.name})
    return result


@router.post("/schedules/{schedule_id}/stop")
async def stop_schedule(schedule_id: int, user=Depends(current_user), session=Depends(db)):
    require(user, "admin", "teacher")
    rule = await session.scalar(select(ClassSchedule).where(ClassSchedule.id == schedule_id).with_for_update())
    if not rule or (user.role == "teacher" and rule.teacher_id != user.id):
        raise HTTPException(404, "Schedule not found")
    rule.active = False
    for c in (await session.scalars(select(ClassSession).where(
        ClassSession.schedule_id == rule.id, ClassSession.starts_at > now()))).all():
        c.cancelled = True
    audit(session, user, "stop recurring schedule")
    await session.commit()
    return {"stopped": True}


@router.get("/students/{student_id}/summary")
async def summary(student_id: int, timezone_name: str = Query(default="Asia/Karachi", max_length=80),
    user=Depends(current_user), session=Depends(db)):
    learner = await check_student(session, user, student_id)
    if not learner:
        raise HTTPException(404, "Student not found")
    try:
        zone = ZoneInfo(timezone_name)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(422, "Choose a valid IANA timezone")
    query = select(ClassSession).where(ClassSession.cancelled == False,
        ClassSession.id.in_(select(Enrollment.session_id).where(Enrollment.student_id == student_id)))
    if user.role == "teacher":
        query = query.where(ClassSession.teacher_id == user.id)
    lessons = (await session.scalars(query.order_by(ClassSession.starts_at))).all()
    marks = {a.session_id: a.present for a in (await session.scalars(select(Attendance).where(
        Attendance.student_id == student_id, Attendance.session_id.in_([c.id for c in lessons])))).all()}
    current = now()
    elapsed = [c for c in lessons if c.starts_at + timedelta(minutes=c.duration) <= current]
    def counts(items):
        present = sum(marks.get(c.id) is True for c in items)
        absent = sum(marks.get(c.id) is False for c in items)
        return {"total": len(items), "present": present, "absent": absent,
            "unrecorded": len(items) - present - absent,
            "rate": round(present * 100 / (present + absent), 1) if present + absent else None}
    months = {}
    for c in elapsed:
        key = c.starts_at.replace(tzinfo=timezone.utc).astimezone(zone).strftime("%Y-%m")
        months.setdefault(key, []).append(c)
    work_query = select(Homework).where(Homework.student_id == student_id)
    resource_query = select(func.count()).select_from(Resource).where(Resource.student_id == student_id)
    if user.role == "teacher":
        work_query = work_query.where(Homework.teacher_id == user.id)
        resource_query = resource_query.where(Resource.teacher_id == user.id)
    work = (await session.scalars(work_query)).all()
    progress = (await session.scalars(select(Progress).where(Progress.student_id == student_id))).all()
    return {"student": public_user(learner), "timezone": timezone_name,
        "attendance": counts(elapsed),
        "months": [{"month": k, **counts(months[k])} for k in sorted(months)[-6:]],
        "lessons": [{**serialize(c, "id title starts_at duration teacher_id"),
            "status": ("present" if marks[c.id] else "absent") if c.id in marks
                else "unrecorded" if c in elapsed else "upcoming"} for c in reversed(lessons[-100:])],
        "progress": [serialize(p, "surah percent notes") for p in progress],
        "homework": {"total": len(work), "completed": sum(w.completed for w in work)},
        "resources": await session.scalar(resource_query)}


@router.get("/admin/conversations")
async def review_conversations(offset: int = Query(default=0, ge=0),
    user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    low = case((Message.sender_id < Message.recipient_id, Message.sender_id), else_=Message.recipient_id)
    high = case((Message.sender_id < Message.recipient_id, Message.recipient_id), else_=Message.sender_id)
    teacher_ids = select(User.id).where(User.role == "teacher")
    learner_ids = select(User.id).where(User.role.in_(["student", "parent"]))
    rows = (await session.execute(select(low.label("first"), high.label("second"),
        func.count(Message.id).label("count"), func.max(Message.created_at).label("latest"))
        .where(or_(and_(Message.sender_id.in_(teacher_ids), Message.recipient_id.in_(learner_ids)),
            and_(Message.recipient_id.in_(teacher_ids), Message.sender_id.in_(learner_ids))))
        .group_by(low, high).order_by(func.max(Message.created_at).desc(), low, high).offset(offset).limit(100))).all()
    result = []
    for row in rows:
        first, second = await session.get(User, row.first), await session.get(User, row.second)
        result.append({"first": public_user(first), "second": public_user(second),
            "count": row._mapping["count"], "latest": row.latest})
    audit(session, user, "list supervised teacher conversations")
    await session.commit()
    return result


@router.get("/admin/conversations/{first_id}/{second_id}")
async def review_thread(first_id: int, second_id: int, before_id: int | None = Query(default=None, ge=1),
    user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    first, second = await session.get(User, first_id), await session.get(User, second_id)
    if not first or not second or {first.role, second.role} not in ({"teacher", "student"}, {"teacher", "parent"}):
        raise HTTPException(404, "Supervised conversation not found")
    query = select(Message).where(or_(and_(Message.sender_id == first_id, Message.recipient_id == second_id),
        and_(Message.sender_id == second_id, Message.recipient_id == first_id)))
    if before_id:
        query = query.where(Message.id < before_id)
    rows = (await session.scalars(query.order_by(Message.id.desc()).limit(100))).all()
    audit(session, user, f"review conversation {min(first_id,second_id)}:{max(first_id,second_id)}")
    await session.commit()
    return [serialize(r, "id sender_id recipient_id text created_at") for r in reversed(rows)]
