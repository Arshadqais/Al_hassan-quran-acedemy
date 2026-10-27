# Connected-app validation

The implementation was exercised in the development workspace. These results describe that workspace, not a remote installation on the academy owner's laptop.

- 24 backend tests passed with isolated SQLite and PostgreSQL databases. Coverage includes authorization, all 30 para routes, cache preservation, rejection of incomplete Quran responses, participant-only live chat updates, WebSocket origin/authentication checks, logout revocation, and private video grants.
- 15 Flutter tests passed, including Quran navigation, provider-error recovery, WebSocket authentication/reconnect, four portal layouts, and account workflows.
- Eight launcher tests passed. Existing settings/accounts are preserved and incomplete provider setup is reported explicitly.
- An isolated local LiveKit server and PostgreSQL test database were used with two browser sessions and simulated media devices. Both directions received audio packets and decoded camera video; the student decoded the teacher's screen-share stream; private text chat arrived while the calls stayed active. Password/session revocation disconnected the active classroom's media.
- The media test used a test-provider URL replacement targeting loopback, with a real signed backend room grant and real LiveKit/WebRTC. It was not a call through the owner's LiveKit Cloud project or across two internet connections. No real student data or physical camera/microphone was used.

The development workspace initially denied outbound access to `api.alquran.cloud`; the required domain additions were saved in its environment draft. Quran parser/cache/API tests used clearly labelled synthetic fixtures. Those fixtures are not installed in the application's Quran cache. A successful provider download and text display must be verified on the laptop using `download-quran` or the desktop wizard. No scripture was generated as a substitute for a blocked download.

The owner must still enter their actual LiveKit project credentials privately on the laptop, authenticate the provider, keep the laptop API available through public HTTPS for remote users, deploy the frontend with that HTTPS URL, and complete the two-device internet/device-permissions checks in [the laptop guide](laptop-and-internet.md).

## Connected academy modules

The follow-up modules add recurring weekly class rules, scoped student/family
summaries, monthly attendance charts, disclosed audited administrator chat
review, and normalized shared-screen rectangle annotations. The suite now has
29 backend tests (SQLite and isolated PostgreSQL), 24 Flutter tests, and 8 local
launcher tests. Flutter analysis is clean and the release web build succeeds.

A PostgreSQL migration test upgraded an old-schema database containing an
existing teacher/lesson, verified the original lesson remains, verified its new
cancelled flag is false, and ran Alembic's schema check. Recurrence tests cover
rolling horizon expansion, duplicate prevention, stopping future lessons without
removing history, role/assignment limits, timezone validation, and daylight-saving
gaps/overlaps. Summary tests distinguish absent and unrecorded attendance and
reject unrelated parents/students. Chat review tests verify role gates, sender
attribution, pagination, and access audit entries. Widget tests cover family
selection, charts, weekly schedule creation, read-only review, rectangle gestures,
and rejection of invalid annotation packets.

A real local LiveKit/WebRTC check with simulated camera, microphone, and screen
confirmed two-way media, teacher screen sharing, a yellow rectangle delivered to
a student at a different viewport size (1440x1000 vs 1024x768), synchronized
Clear highlights, and persisted in-call contact chat. Screenshots visibly show
the rectangle on the student's received screen track. This is isolated local
transport verification; the owner's actual devices and internet connection still
need their normal operational test.

## WhatsApp class reminder integration

The reminder update passes 41 backend tests, 26 Flutter tests, and 8 launcher
tests. The additive contact/outbox migration was applied to an isolated
PostgreSQL database containing a pre-update lesson; that lesson remained and
Alembic reported no schema differences. The backend suite runs on both SQLite
and isolated PostgreSQL. Flutter analysis and the web release build pass.

WhatsApp tests use HTTPX mock transports only: no real WhatsApp message was sent.
They cover own-account opt-in, phone validation/privacy, teacher/student/linked
parent routing, shared-number deduplication, durable restart protection,
rate-limit retry timing, cancellation and opt-out rechecks, network uncertainty,
signed/out-of-order/early delivery receipts, read-only sender/template
verification, backend worker lifecycle, and shared-number changes after queuing.
Flutter tests cover opt-in/opt-out and distinguish Accepted from Delivered.

The actual client's Meta business sender, approved template, permissions, billing,
public webhook subscription, and receipt of a real message on an opted-in phone
must be verified during [WhatsApp onboarding](whatsapp-reminders.md). No real
provider credentials were configured in the development environment.
