"""Expand saved weekly rules into a rolling 45-day classroom calendar.

No scheduler daemon is required: opening Classes refreshes the horizon. Unique
occurrence keys and a savepoint make repeated/concurrent expansion idempotent.
"""
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from app.models import ClassSchedule, ScheduleEnrollment, ClassSession, Enrollment, now


def occurrence(day, local_time, zone):
    local = datetime.combine(day, time.fromisoformat(local_time), tzinfo=ZoneInfo(zone))
    utc = local.astimezone(timezone.utc)
    # Spring-forward gaps have no actual wall-clock occurrence. At a fall-back
    # overlap choose the first occurrence (fold=0), never create two classes.
    if utc.astimezone(local.tzinfo).replace(tzinfo=None) != local.replace(tzinfo=None):
        return None
    return utc.replace(tzinfo=None)


async def expand_schedules(session, user, current=None):
    current = current or now()
    query = select(ClassSchedule).where(ClassSchedule.active == True)
    if user.role == "teacher":
        query = query.where(ClassSchedule.teacher_id == user.id)
    elif user.role != "admin":
        linked = select(ScheduleEnrollment.schedule_id)
        if user.role == "student":
            linked = linked.where(ScheduleEnrollment.student_id == user.id)
        else:
            from app.models import Assignment
            linked = linked.where(ScheduleEnrollment.student_id.in_(
                select(Assignment.student_id).where(Assignment.adult_id == user.id)))
        query = query.where(ClassSchedule.id.in_(linked))
    # Serialize expansion/stop operations for a schedule on PostgreSQL.
    for rule in (await session.scalars(query.order_by(ClassSchedule.id).with_for_update())).all():
        today = current.replace(tzinfo=timezone.utc).astimezone(ZoneInfo(rule.timezone)).date()
        day = max(rule.start_date, today - timedelta(days=1))
        until = min(today + timedelta(days=45), rule.end_date or today + timedelta(days=45))
        students = list((await session.scalars(select(ScheduleEnrollment.student_id).where(
            ScheduleEnrollment.schedule_id == rule.id))).all())
        weekdays = {int(v) for v in rule.weekdays.split(",")}
        existing = set((await session.scalars(select(ClassSession.starts_at).where(
            ClassSession.schedule_id == rule.id))).all())
        if existing:
            last_generated = max(existing).replace(tzinfo=timezone.utc).astimezone(ZoneInfo(rule.timezone)).date()
            day = max(rule.start_date, min(day, last_generated))
        while day <= until:
            stamp = occurrence(day, rule.local_time, rule.timezone) if day.weekday() in weekdays else None
            if stamp is not None and stamp not in existing:
                try:
                    async with session.begin_nested():
                        item = ClassSession(title=rule.title, teacher_id=rule.teacher_id,
                            starts_at=stamp, duration=rule.duration, category=rule.category, schedule_id=rule.id)
                        session.add(item)
                        await session.flush()
                        session.add_all(Enrollment(session_id=item.id, student_id=s) for s in students)
                        await session.flush()
                except IntegrityError:
                    # A concurrent request generated this same occurrence.
                    found = await session.scalar(select(ClassSession.id).where(
                        ClassSession.schedule_id == rule.id, ClassSession.starts_at == stamp))
                    if found is None:
                        raise
            day += timedelta(days=1)
    await session.commit()
