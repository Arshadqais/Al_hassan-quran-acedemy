# Academy interface refresh

The interface follows the supplied mobile reference: ivory and emerald surfaces,
muted gold accents, mosque arch artwork, rounded white cards, compact dashboard
metrics, and mobile bottom navigation. Desktop layouts retain a full sidebar.
The academy name remains Al Hassan Online Quran Academy.

- The welcome screen and login share a botanical background and local vector
  artwork. No external image service is required to render the interface.
- Admin quick actions create students and teachers with the correct role selected,
  schedule classes, and open reports.
- Teacher, student, and parent dashboards use authorized API records. Empty
  records remain empty; dashboard statistics are not populated with demo values.
- Students see Quran progress and upcoming lessons. Parents can select a linked
  child to view their progress. Initials represent people without uploaded photos.
- Classes have Upcoming/Past tabs; times use the device timezone.
- Attendance has month navigation and day filtering against saved class records.
- Resources have title search; private messages retain their existing delivery.
- Classroom controls have round media buttons and a prominent leave button.

Account creation, authorization, Quran text, database schemas, and LiveKit grants
are unchanged. OAuth login, public self-registration, resource media uploads, and
profile photo uploads are not added by this visual refresh.

## Validation

Flutter analysis, 19 Flutter tests, and the release web build pass. Tests cover
mobile navigation for all four live roles, class tabs, calendar navigation,
resource search, existing demo interactions, authentication, Quran reading, and
message events. Desktop (1440 x 1000) and mobile (390 x 844) Chromium checks cover
welcome/login and all four connected dashboard layouts using synthetic API
fixtures. Browser screenshots are review artifacts; fixtures are not installed in
the academy database. Internet calls on the owner's devices remain a separate
operational check.

## Update an existing laptop checkout

Stop the running Flutter frontend first. Preserve a locally generated lockfile if
Git reports it would be overwritten:

```bash
git stash push -m "Preserve local Flutter lockfile" -- frontend/pubspec.lock
git pull origin main
cd frontend
flutter pub get
flutter run -d chrome --web-port=8091 --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Keep the backend running with `python3 scripts/local.py backend --web-port 8091`
and Docker Desktop open. Existing private `backend/.env` and database contents
are retained. Published Pages still requires the owner's public HTTPS backend
configuration for real sign-in.

Subsequent connected modules are documented in [academy modules](academy-modules.md), including the additive schedule migration and audited administrator chat supervision.
