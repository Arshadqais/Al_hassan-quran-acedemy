# WhatsApp class reminders

Class reminders use the official Meta WhatsApp Business Cloud API. They are sent
10 minutes before class by default to opted-in teachers, enrolled students, and
parents linked to enrolled students. No browser needs to remain open. The
academy backend, PostgreSQL, and internet connection must remain running.

This integration is inactive until a business sender, token, and approved
reminder template are configured. No personal WhatsApp browser automation or
unofficial WhatsApp library is used.

## 1. Prepare the client's Meta account

1. Open [Meta for Developers](https://developers.facebook.com/), create/select a
   business app, and add the **WhatsApp** product.
2. Complete the WhatsApp Business setup and register a sender number. The API
   setup page supplies its **Phone number ID** and **WhatsApp Business Account
   ID**. These IDs are not the number written with a country code.
3. Create a production-appropriate access token with
   `whatsapp_business_messaging` and `whatsapp_business_management` permissions,
   assigned to the client's WhatsApp business assets. Meta's temporary test token
   expires; do not depend on it for ongoing academy use.
4. During Meta's testing stage, add and verify each allowed recipient number in
   API setup. Real-recipient availability depends on completing Meta's business
   onboarding and current account restrictions.

The client should own the business account, sender, and any Meta billing setup.
Messages are subject to Meta's template approval, messaging rules, and charges.
Never put access tokens/app secrets in Flutter, GitHub, screenshots, or chat.

## 2. Create the approved reminder template

In **WhatsApp Manager → Message templates**, submit a utility reminder template
with positional body parameters, for example name `class_reminder`:

> Assalamu Alaikum. Your {{1}} class starts at {{2}}. Please open Al Hassan Online Quran Academy to join.

- `{{1}}`: class title, e.g. `Quran Recitation`.
- `{{2}}`: date/time with timezone, e.g. `Sun, 01 Nov 2026 at 09:00 (Asia/Karachi)`.
- Match the language code exactly (e.g. `en_US` or `en_GB`) to the approved
  language in WhatsApp Manager. The wizard lets you choose it.
- The body must have exactly those two positional parameters. Dynamic/media
  headers, named parameters, and dynamic URL buttons are not supported by this
  sender. A static website button to the academy website is permitted.
- Wait until Meta reports **APPROVED**. Approval is controlled by Meta.

## 3. Configure privately on the academy computer

After pulling this update and applying its database migration through the normal
backend launcher, run from the repository root:

```bash
python3 scripts/local.py configure-whatsapp
```

Enter sender ID, business-account ID, approved template name/language, supported
Graph API version, reminder minutes (1–120), and the timezone for one-off classes.
The default lead time is 10 minutes and the default timezone is Asia/Karachi.
Recurring classes use their saved schedule timezone instead.

The token and optional webhook app secret/verification token are hidden prompts.
The wizard makes read-only requests to verify the sender belongs to the business
account and the template is approved with compatible parameters. It sends no
WhatsApp message. It preserves existing PostgreSQL/LiveKit settings and writes
only the ignored `backend/.env` with mode 0600. Restart the backend afterward.

If this Mac previously needed `SSL_CERT_FILE` for LiveKit, use the same trusted
certificate setting when running the wizard/backend. Keep TLS verification on.

## 4. Each recipient opts in

Sign in as a teacher, student, or parent and open **Account → Set WhatsApp class
reminders**, or **WhatsApp reminders** in the menu. Enter an international number
such as `+923001234567`, check consent, and save. Use a number the account holder
owns or has permission to use. No phone number is shared through People,
Contacts, or Messages. Recipients can uncheck consent and save to stop future
unsent reminders.

The administrator must enroll students in classes, link teachers to students,
and link parents to their own children. An unrelated parent/teacher receives
nothing. A shared family phone gets only one reminder per class, even if both
the parent and student opted in. Changing a phone does not create another
reminder for an account that already has one for the same class.

## 5. Optional signed delivery receipts

Without receipts, **Accepted by WhatsApp** only means Meta accepted the request.
It does not establish delivery. To see actual sent/delivered/read/failed events:

1. Enter the Meta **App secret** and a private, random webhook verification token
   using `configure-whatsapp`, then restart the backend.
2. In the Meta app's WhatsApp webhook configuration, set callback URL:
   `https://YOUR-PUBLIC-API/api/whatsapp/webhook`.
3. Enter the same verification token in Meta and subscribe to the **messages**
   webhook field for this business account. Use a stable HTTPS API address for
   normal client operation; a stopped/changed temporary tunnel cannot receive
   receipts.
4. The backend validates the challenge, checks each POST's HMAC-SHA256 signature,
   and matches the business account and sender ID. It stores only the matching
   reminder status, not incoming WhatsApp chat content. This is not two-way
   WhatsApp chat or an incoming-message inbox.

Read events depend on Meta and recipient read-receipt settings. Duplicate and
out-of-order callbacks cannot move a reminder from Read back to Sent. A signed
early receipt can be correlated while its original send request is completing.

## 6. Monitor and test

Open **Admin → Reminder delivery**. It shows configuration readiness and the last
100 reminder records, with names, masked phone endings, and status:

- Queued / Sending: awaiting submission or currently sending.
- Accepted by WhatsApp: accepted by Meta; delivery not yet established.
- Sent / Delivered / Read: signed receipt received.
- Failed: provider rejection, exhausted rate-limit retries, or failed delivery.
- Result unknown: a timeout, server error, or interrupted send may have been
  accepted. The system does not automatically resend an ambiguous result.
- Skipped: lesson cancelled/started, recipient opted out, phone changed, or
  enrollment/parent linkage no longer permits delivery.

For a real check, use consenting test recipients, an approved template, and a
lesson around 8–10 minutes in the future. Confirm the recipient's phone receives
the message and check its delivery receipt. This incurs a real provider request;
the configuration wizard and automated tests do not send test messages.

## Timing and reliability

FastAPI starts a background worker with its application lifespan. Every 30
seconds it queues upcoming reminders, and periodically refreshes recurring class
occurrences. A database-backed outbox survives restarts. Unique keys prevent
re-queueing the same class/phone or class/account. Numbers, consent, active users,
class cancellation, enrollment, and parent links are rechecked before sending.

Only an unambiguous HTTP 429 rejection is retried automatically (up to three
attempts before class starts). Ambiguous network/server failures and interrupted
sends are marked unknown instead of risking duplicates. This is not an
exactly-once delivery guarantee: the API and external provider cannot share one
database transaction. Meta may delay or reject messages.

Reminders are not sent after a class has started, including after a laptop wakes
from sleep. Keep the academy computer awake and connected. Run one backend
worker as currently required by the in-memory live-chat notification broker.
