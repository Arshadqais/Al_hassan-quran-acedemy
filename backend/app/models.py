"""Academy records; scope is enforced by the API in addition to foreign keys."""

from datetime import datetime, timezone, date
from sqlalchemy import String, ForeignKey, UniqueConstraint, CheckConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    email: Mapped[str] = mapped_column(String(160), unique=True)
    password_hash: Mapped[str] = mapped_column(String(256))
    role: Mapped[str] = mapped_column(String(12))
    level: Mapped[str] = mapped_column(String(80), default="Level 1")
    active: Mapped[bool] = mapped_column(default=True)
    __table_args__ = (
        CheckConstraint("role IN ('admin','teacher','student','parent')"),
    )


class Assignment(Base):
    __tablename__ = "assignments"
    id: Mapped[int] = mapped_column(primary_key=True)
    adult_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    __table_args__ = (UniqueConstraint("adult_id", "student_id"),)


class LoginSession(Base):
    __tablename__ = "login_sessions"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime]


class ClassSchedule(Base):
    __tablename__ = "class_schedules"
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(100))
    teacher_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    start_date: Mapped[date]
    end_date: Mapped[date | None]
    local_time: Mapped[str] = mapped_column(String(5))
    timezone: Mapped[str] = mapped_column(String(80))
    weekdays: Mapped[str] = mapped_column(String(13))
    duration: Mapped[int] = mapped_column(default=30)
    category: Mapped[str] = mapped_column(String(20), default="Individual")
    active: Mapped[bool] = mapped_column(default=True)


class ScheduleEnrollment(Base):
    __tablename__ = "schedule_enrollments"
    id: Mapped[int] = mapped_column(primary_key=True)
    schedule_id: Mapped[int] = mapped_column(ForeignKey("class_schedules.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    __table_args__ = (UniqueConstraint("schedule_id", "student_id"),)


class ClassSession(Base):
    __tablename__ = "class_sessions"
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(100))
    teacher_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    starts_at: Mapped[datetime]
    duration: Mapped[int] = mapped_column(default=30)
    category: Mapped[str] = mapped_column(String(20), default="Individual")
    schedule_id: Mapped[int | None] = mapped_column(ForeignKey("class_schedules.id"), index=True)
    cancelled: Mapped[bool] = mapped_column(default=False)
    __table_args__ = (UniqueConstraint("schedule_id", "starts_at", name="uq_schedule_occurrence"),)


class Enrollment(Base):
    __tablename__ = "enrollments"
    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("class_sessions.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    __table_args__ = (UniqueConstraint("session_id", "student_id"),)


class Attendance(Base):
    __tablename__ = "attendance"
    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("class_sessions.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    present: Mapped[bool]
    __table_args__ = (UniqueConstraint("session_id", "student_id"),)


class Progress(Base):
    __tablename__ = "quran_progress"
    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    surah: Mapped[str] = mapped_column(String(80))
    percent: Mapped[int]
    notes: Mapped[str] = mapped_column(String(1000), default="")
    __table_args__ = (
        UniqueConstraint("student_id", "surah"),
        CheckConstraint("percent >= 0 AND percent <= 100"),
    )


class Homework(Base):
    __tablename__ = "homework"
    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    teacher_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(160))
    completed: Mapped[bool] = mapped_column(default=False)


class Resource(Base):
    __tablename__ = "resources"
    id: Mapped[int] = mapped_column(primary_key=True)
    teacher_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(160))
    content: Mapped[str] = mapped_column(String(20000))


class Message(Base):
    __tablename__ = "messages"
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    recipient_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    text: Mapped[str] = mapped_column(String(2000))
    created_at: Mapped[datetime] = mapped_column(default=now)


class Feedback(Base):
    __tablename__ = "feedback"
    id: Mapped[int] = mapped_column(primary_key=True)
    parent_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    rating: Mapped[int]
    text: Mapped[str] = mapped_column(String(1500))
    __table_args__ = (CheckConstraint("rating >= 1 AND rating <= 5"),)


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    actor_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    action: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(default=now)
