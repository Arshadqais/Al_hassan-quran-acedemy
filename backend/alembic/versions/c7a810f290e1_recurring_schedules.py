"""Recurring class schedules; preserve existing sessions and academic records."""
from alembic import op
import sqlalchemy as sa

revision = "c7a810f290e1"
down_revision = "b6353f1c434b"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("class_schedules",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("teacher_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("local_time", sa.String(5), nullable=False),
        sa.Column("timezone", sa.String(80), nullable=False),
        sa.Column("weekdays", sa.String(13), nullable=False),
        sa.Column("duration", sa.Integer(), nullable=False),
        sa.Column("category", sa.String(20), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False))
    op.create_index("ix_class_schedules_teacher_id", "class_schedules", ["teacher_id"])
    op.create_table("schedule_enrollments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("schedule_id", sa.Integer(), sa.ForeignKey("class_schedules.id"), nullable=False),
        sa.Column("student_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.UniqueConstraint("schedule_id", "student_id"))
    op.create_index("ix_schedule_enrollments_schedule_id", "schedule_enrollments", ["schedule_id"])
    op.create_index("ix_schedule_enrollments_student_id", "schedule_enrollments", ["student_id"])
    with op.batch_alter_table("class_sessions") as batch:
        batch.add_column(sa.Column("schedule_id", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("cancelled", sa.Boolean(), server_default=sa.false(), nullable=False))
        batch.create_foreign_key("fk_session_schedule", "class_schedules", ["schedule_id"], ["id"])
        batch.create_index("ix_class_sessions_schedule_id", ["schedule_id"])
        batch.create_unique_constraint("uq_schedule_occurrence", ["schedule_id", "starts_at"])
    with op.batch_alter_table("class_sessions") as batch:
        batch.alter_column("cancelled", server_default=None)


def downgrade():
    with op.batch_alter_table("class_sessions") as batch:
        batch.drop_constraint("uq_schedule_occurrence", type_="unique")
        batch.drop_index("ix_class_sessions_schedule_id")
        batch.drop_constraint("fk_session_schedule", type_="foreignkey")
        batch.drop_column("cancelled")
        batch.drop_column("schedule_id")
    op.drop_table("schedule_enrollments")
    op.drop_table("class_schedules")
