"""Opt-in contacts and a durable class-reminder outbox."""
from alembic import op
import sqlalchemy as sa
revision = "a91051c72b0e"
down_revision = "c7a810f290e1"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("reminder_contacts",
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("phone", sa.String(16), nullable=False),
        sa.Column("consent", sa.Boolean(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False))
    op.create_table("whatsapp_reminders",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("session_id", sa.Integer(), sa.ForeignKey("class_sessions.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("phone", sa.String(16), nullable=False),
        sa.Column("starts_at", sa.DateTime(), nullable=False),
        sa.Column("state", sa.String(16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(), nullable=False),
        sa.Column("claimed_at", sa.DateTime(), nullable=True),
        sa.Column("provider_id", sa.String(256), nullable=True),
        sa.Column("error_code", sa.String(80), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("provider_id"),
        sa.UniqueConstraint("session_id", "phone", name="uq_class_whatsapp_phone"),
        sa.UniqueConstraint("session_id", "user_id", name="uq_class_whatsapp_user"))
    for column in ("session_id", "user_id", "state"):
        op.create_index("ix_whatsapp_reminders_" + column, "whatsapp_reminders", [column])


def downgrade():
    op.drop_table("whatsapp_reminders")
    op.drop_table("reminder_contacts")
