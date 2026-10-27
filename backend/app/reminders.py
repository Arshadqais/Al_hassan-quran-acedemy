"""Opt-in WhatsApp Business template reminders. Never logs tokens or phone numbers."""
import asyncio
from datetime import timedelta, timezone
import hashlib
import hmac
import json
import logging
import os
import re
from types import SimpleNamespace
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select, or_
from sqlalchemy.exc import IntegrityError
from app.db.database import env, Session
from app.models import (ReminderContact, WhatsAppReminder, User, ClassSession,
    Assignment, Enrollment, ClassSchedule, now)
from app.security import current_user, db
from app.api import require, audit
from app.recurrence import expand_schedules

router = APIRouter()
logger = logging.getLogger(__name__)
GRAPH_HOST = "https://graph.facebook.com"


def configuration():
    values = {**env, **os.environ}
    return {k: values.get(k, "") for k in (
        "WHATSAPP_PHONE_NUMBER_ID", "WHATSAPP_WABA_ID", "WHATSAPP_ACCESS_TOKEN",
        "WHATSAPP_TEMPLATE_NAME", "WHATSAPP_TEMPLATE_LANGUAGE", "WHATSAPP_API_VERSION",
        "WHATSAPP_APP_SECRET", "WHATSAPP_VERIFY_TOKEN", "REMINDER_MINUTES", "REMINDER_TIMEZONE")}


def settings(values=None):
    values = values if values is not None else configuration()
    result = dict(values)
    result["WHATSAPP_API_VERSION"] = values.get("WHATSAPP_API_VERSION") or "v23.0"
    result["WHATSAPP_TEMPLATE_LANGUAGE"] = values.get("WHATSAPP_TEMPLATE_LANGUAGE") or "en"
    result["REMINDER_TIMEZONE"] = values.get("REMINDER_TIMEZONE") or "Asia/Karachi"
    try:
        minutes = int(values.get("REMINDER_MINUTES") or "10")
        ZoneInfo(result["REMINDER_TIMEZONE"])
    except (ValueError, ZoneInfoNotFoundError):
        return None
    if not 1 <= minutes <= 120:
        return None
    result["minutes"] = minutes
    for field, pattern in [("WHATSAPP_PHONE_NUMBER_ID", r"\d{1,40}"),
        ("WHATSAPP_WABA_ID", r"\d{1,40}"), ("WHATSAPP_API_VERSION", r"v\d{1,3}\.\d"),
        ("WHATSAPP_TEMPLATE_NAME", r"[a-z0-9_]{1,100}"),
        ("WHATSAPP_TEMPLATE_LANGUAGE", r"[a-z]{2,3}(?:_[A-Z]{2})?")]:
        if not re.fullmatch(pattern, result.get(field, "")):
            return None
    if not result.get("WHATSAPP_ACCESS_TOKEN"):
        return None
    return result


class ContactIn(BaseModel):
    phone: str = Field(default="", max_length=16)
    consent: bool = False

    @model_validator(mode="after")
    def valid_phone(self):
        self.phone = self.phone.strip()
        if self.phone and not re.fullmatch(r"\+[1-9]\d{7,14}", self.phone):
            raise ValueError("Use an international number such as +923001234567")
        if self.consent and not self.phone:
            raise ValueError("A phone number is required to opt in")
        return self


@router.get("/api/auth/reminder-contact")
async def own_contact(user=Depends(current_user), session=Depends(db)):
    item = await session.get(ReminderContact, user.id)
    return {"phone": item.phone if item else "", "consent": item.consent if item else False}


@router.put("/api/auth/reminder-contact")
async def save_contact(data: ContactIn, user=Depends(current_user), session=Depends(db)):
    item = await session.get(ReminderContact, user.id)
    if not item:
        item = ReminderContact(user_id=user.id)
        session.add(item)
    item.phone, item.consent, item.updated_at = data.phone, data.consent, now()
    audit(session, user, "update own WhatsApp reminder consent")
    await session.commit()
    return {"saved": True}


async def recipients(session, lesson):
    student_ids = select(Enrollment.student_id).where(Enrollment.session_id == lesson.id)
    parents = select(Assignment.adult_id).where(Assignment.student_id.in_(student_ids))
    rows = (await session.execute(select(User, ReminderContact).join(ReminderContact,
        ReminderContact.user_id == User.id).where(User.active == True, ReminderContact.consent == True,
            or_(User.id == lesson.teacher_id,
                (User.role == "student") & User.id.in_(student_ids),
                (User.role == "parent") & User.id.in_(parents))).order_by(User.id))).all()
    # A family may reuse one number: send one reminder per class/number.
    return {contact.phone: user.id for user, contact in rows if contact.phone}


async def queue_reminders(session, config, current=None):
    current = current or now()
    if config is None:
        return 0
    lessons = (await session.scalars(select(ClassSession).where(ClassSession.cancelled == False,
        ClassSession.starts_at > current,
        ClassSession.starts_at <= current + timedelta(minutes=config["minutes"])))).all()
    count = 0
    for lesson in lessons:
        for phone, user_id in (await recipients(session, lesson)).items():
            if await session.scalar(select(WhatsAppReminder.id).where(
                WhatsAppReminder.session_id == lesson.id, or_(WhatsAppReminder.phone == phone, WhatsAppReminder.user_id == user_id))):
                continue
            try:
                async with session.begin_nested():
                    session.add(WhatsAppReminder(session_id=lesson.id, user_id=user_id, phone=phone,
                        starts_at=lesson.starts_at, next_attempt_at=current))
                    await session.flush()
                count += 1
            except IntegrityError:
                # Only suppress a duplicate-key race, not another integrity error.
                duplicate = await session.scalar(select(WhatsAppReminder.id).where(
                    WhatsAppReminder.session_id == lesson.id,
                    or_(WhatsAppReminder.phone == phone, WhatsAppReminder.user_id == user_id)))
                if duplicate is None:
                    raise
    await session.commit()
    return count


async def send_template(client, config, phone, title, when, ident):
    """Returns accepted/failed/retry/unknown; never assumes HTTP acceptance is delivery."""
    payload = {"biz_opaque_callback_data": f"academy-reminder-{ident}", "messaging_product": "whatsapp", "to": phone[1:], "type": "template",
        "template": {"name": config["WHATSAPP_TEMPLATE_NAME"],
            "language": {"code": config["WHATSAPP_TEMPLATE_LANGUAGE"]},
            "components": [{"type": "body", "parameters": [
                {"type": "text", "text": title}, {"type": "text", "text": when}]}]}}
    try:
        response = await client.post(f"{GRAPH_HOST}/{config['WHATSAPP_API_VERSION']}/{config['WHATSAPP_PHONE_NUMBER_ID']}/messages",
            headers={"Authorization": "Bearer " + config["WHATSAPP_ACCESS_TOKEN"]}, json=payload)
    except (httpx.TransportError, httpx.TimeoutException):
        return "unknown", None, "network_result_unknown"
    if response.status_code == 429:
        return "retry", None, "rate_limited"
    if response.status_code >= 500:
        return "unknown", None, "provider_result_unknown"
    try:
        data = response.json()
    except ValueError:
        data = {}
    if response.is_success:
        messages = data.get("messages", []) if isinstance(data, dict) else []
        message_id = messages[0].get("id") if messages and isinstance(messages[0], dict) else None
        if isinstance(message_id, str) and 1 <= len(message_id) <= 256:
            return "accepted", message_id, ""
        return "unknown", None, "provider_result_unknown"
    code = data.get("error", {}).get("code") if isinstance(data, dict) and isinstance(data.get("error"), dict) else None
    return "failed", None, f"meta_{code}" if isinstance(code, int) else f"http_{response.status_code}"


async def dispatch_one(factory, client, config, current=None):
    current = current or now()
    async with factory() as session:
        item = await session.scalar(select(WhatsAppReminder).where(WhatsAppReminder.state == "pending",
            WhatsAppReminder.next_attempt_at <= current).order_by(WhatsAppReminder.id).limit(1).with_for_update(skip_locked=True))
        if not item:
            return False
        lesson = await session.get(ClassSession, item.session_id)
        eligible = await recipients(session, lesson) if lesson and not lesson.cancelled else {}
        if not lesson or lesson.starts_at <= current or lesson.starts_at != item.starts_at or item.phone not in eligible:
            item.state, item.error_code, item.updated_at = "skipped", "cancelled_expired_or_opted_out", current
            await session.commit()
            return True
        # Keep the original account key stable if a family shares/changes numbers.
        item.state, item.claimed_at = "sending", current
        item.attempts += 1
        zone = config["REMINDER_TIMEZONE"]
        if lesson.schedule_id:
            rule = await session.get(ClassSchedule, lesson.schedule_id)
            zone = rule.timezone
        when = lesson.starts_at.replace(tzinfo=timezone.utc).astimezone(ZoneInfo(zone)).strftime("%a, %d %b %Y at %H:%M") + f" ({zone})"
        ident, phone, title = item.id, item.phone, lesson.title
        await session.commit()
    state, provider_id, error = await send_template(client, config, phone, title, when, ident)
    async with factory() as session:
        item = await session.get(WhatsAppReminder, ident)
        item.updated_at = current
        # A signed receipt can arrive before the HTTP request completes.
        if item.state in ("sent", "delivered", "read", "failed") and item.provider_id:
            return True
        item.provider_id, item.error_code = provider_id, error
        if state == "retry":
            item.state = "pending" if item.attempts < 3 else "failed"
            item.next_attempt_at = current + timedelta(seconds=60 * item.attempts)
        else:
            item.state = state
        await session.commit()
    return True


async def recover_uncertain(session, current=None):
    current = current or now()
    for item in (await session.scalars(select(WhatsAppReminder).where(
        WhatsAppReminder.state == "sending", WhatsAppReminder.claimed_at < current - timedelta(minutes=2)))).all():
        item.state, item.error_code, item.updated_at = "unknown", "interrupted_result_unknown", current
    await session.commit()


async def reminder_worker(factory=Session):
    last_expanded = None
    async with httpx.AsyncClient(timeout=15) as client:
        while True:
            try:
                config = settings()
                if config:
                    current = now()
                    async with factory() as session:
                        if last_expanded is None or current - last_expanded >= timedelta(minutes=5):
                            await expand_schedules(session, SimpleNamespace(role="admin"))
                            last_expanded = current
                        await recover_uncertain(session, current)
                        await queue_reminders(session, config, current)
                    for _ in range(50):
                        if not await dispatch_one(factory, client, config):
                            break
            except asyncio.CancelledError:
                raise
            except Exception:
                # Exceptions may contain request/recipient details; log no payloads.
                logger.warning("Class reminder cycle failed; check database/provider configuration in the admin screen.")
            await asyncio.sleep(30)


@router.get("/api/admin/reminders")
async def reminder_status(user=Depends(current_user), session=Depends(db)):
    require(user, "admin")
    config = settings()
    values = configuration()
    rows = (await session.scalars(select(WhatsAppReminder).order_by(WhatsAppReminder.id.desc()).limit(100))).all()
    result = []
    for row in rows:
        learner, lesson = await session.get(User, row.user_id), await session.get(ClassSession, row.session_id)
        result.append({"id": row.id, "recipient": learner.name, "class_title": lesson.title,
            "phone": "••••" + row.phone[-4:], "starts_at": row.starts_at, "state": row.state,
            "attempts": row.attempts, "error_code": row.error_code, "updated_at": row.updated_at})
    return {"configured": config is not None, "minutes": config["minutes"] if config else 10,
        "receipts_configured": bool(values.get("WHATSAPP_APP_SECRET") and values.get("WHATSAPP_VERIFY_TOKEN")),
        "deliveries": result}


@router.get("/api/whatsapp/webhook")
async def verify_webhook(request: Request):
    values = configuration()
    supplied, expected = request.query_params.get("hub.verify_token", ""), values.get("WHATSAPP_VERIFY_TOKEN", "")
    if not expected or request.query_params.get("hub.mode") != "subscribe" or not hmac.compare_digest(supplied.encode(), expected.encode()):
        raise HTTPException(403, "Invalid verification")
    return PlainTextResponse(request.query_params.get("hub.challenge", ""))


@router.post("/api/whatsapp/webhook")
async def delivery_receipts(request: Request, session=Depends(db)):
    values = configuration()
    secret = values.get("WHATSAPP_APP_SECRET", "")
    if not secret:
        raise HTTPException(503, "Delivery receipts are not configured")
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw) > 131072:
            raise HTTPException(413, "Payload too large")
    signature = "sha256=" + hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature.encode(), request.headers.get("X-Hub-Signature-256", "").encode()):
        raise HTTPException(403, "Invalid signature")
    try:
        payload = json.loads(raw)
        for entry in payload.get("entry", []):
            if str(entry.get("id")) != values.get("WHATSAPP_WABA_ID"):
                continue
            for change in entry.get("changes", []):
                value = change.get("value", {})
                if str(value.get("metadata", {}).get("phone_number_id")) != values.get("WHATSAPP_PHONE_NUMBER_ID"):
                    continue
                for receipt in value.get("statuses", []):
                    mid, status = receipt.get("id"), receipt.get("status")
                    if not isinstance(mid, str) or status not in ("sent", "delivered", "read", "failed"):
                        continue
                    row = await session.scalar(select(WhatsAppReminder).where(WhatsAppReminder.provider_id == mid))
                    if row is None:
                        callback = receipt.get("biz_opaque_callback_data", "")
                        matched = re.fullmatch(r"academy-reminder-(\d{1,12})", callback) if isinstance(callback, str) else None
                        if matched:
                            row = await session.get(WhatsAppReminder, int(matched[1]))
                            if row is not None and row.state == "sending" and row.provider_id is None:
                                row.provider_id = mid
                            else:
                                row = None
                    if row is None:
                        continue
                    ranks = {"accepted": 0, "sent": 1, "delivered": 2, "read": 3}
                    if status == "failed" and row.state not in ("delivered", "read"):
                        row.state, row.error_code = "failed", "provider_delivery_failed"
                    elif status != "failed" and ranks.get(status, -1) > ranks.get(row.state, -1):
                        row.state, row.error_code = status, ""
                    row.updated_at = now()
    except (ValueError, TypeError, AttributeError):
        raise HTTPException(400, "Invalid receipt")
    await session.commit()
    return {"received": True}
