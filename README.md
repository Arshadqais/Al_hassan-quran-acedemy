# Al Hassan Online Quran Academy

A responsive Flutter website and academy dashboard, styled in forest green, warm cream, and gold from the supplied design. The Python FastAPI service stores academy records in PostgreSQL.

**Website target:** `https://arshadqais.github.io/Al_hassan-quran-acedemy/`

This URL becomes available after the code is pushed and the repository owner enables GitHub Pages. GitHub Pages serves the website; it cannot run Python or PostgreSQL.

## Website and portals

The public website includes an interactive demonstration with fictional data. Choose Admin, Teacher, Student, or Parent to explore classes, Quran progress, attendance, study resources, homework, messages, and profiles. Demo changes last for the current visit and are never presented as saved academy records.

**Academy sign in** opens the separate live portal when an API URL is configured. The server determines the role. It provides:

- Administrator-created accounts and teacher/student/parent links.
- Individual and group classes plus persistent weekly schedules: set weekdays, local time, and timezone once; the next 45 days expand automatically.
- Consolidated student records, parent/child selection, attendance totals, and monthly attendance charts.
- Teacher-recorded attendance and Quran progress.
- Assigned study notes and homework; students can mark their own work complete.
- Live one-to-one chat for authorized teacher/student/parent/admin contacts, persisted in PostgreSQL, with authenticated WebSocket updates. Administrators can review teacher–student and teacher–parent conversations through an explicitly disclosed, read-only, audited review screen. Chat also remains available during video classes.
- Quran reading by all 30 paras and 114 Surahs, with unchanged Uthmani Arabic, optional Urdu/English translations, and local cached editions.
- Parent feedback, administrative summaries and audit records.
- Opt-in WhatsApp Business reminders before class for teachers, enrolled students, and linked parents, with durable duplicate protection and signed delivery-status receipts. Requires the client’s Meta sender and an approved template; [setup guide](docs/whatsapp-reminders.md).
- Password changes that revoke every active session for the account.
- LiveKit private classroom integration with camera, microphone, teacher screen sharing with synchronized rectangle highlights, and a leave button. Camera and microphone start off. A configured LiveKit service is required.

Sessions are opaque, expire after eight hours, and can be revoked. Passwords use salted PBKDF2-SHA256. Browser session tokens are kept only in memory. Parents see linked children, teachers see assigned students, and students see their own records. Changing an ID in a URL does not bypass those checks.

## Connected laptop app and internet calls

Double-click **`Start Academy.command`** after pulling the updated repository, or run `python3 scripts/local.py desktop`. Its first-run wizard prepares the local Docker database and FastAPI, creates your administrator when needed, downloads all 30 paras, and privately configures your LiveKit project. Later launches start the local app and open it in your browser.

Follow [the complete laptop/internet guide](docs/laptop-and-internet.md) to create the LiveKit project, use the Quran reader, and connect remote students through a public HTTPS tunnel. Database records and messages stay on your laptop; the video provider carries media between participants. Credentials and a real internet/device test remain necessary before declaring video ready.

## Quick local start (macOS / Linux)

Install/open **Docker Desktop**, install Python 3.12+ and Flutter 3.47.8, then run these from your checkout (replace the path if yours is elsewhere):

```bash
cd ~/Desktop/Al_hassan-quran-acedemy
git pull origin main
python3 scripts/local.py setup
python3 scripts/local.py create-admin
python3 scripts/local.py run
```

Open **http://127.0.0.1:8090** and choose **Academy sign in**. Use the administrator credentials you just created. `run` starts PostgreSQL, waits for it, applies migrations, starts the API, checks its database health, and starts Flutter with the correct local API URL and CORS origins. Keep that terminal open; Ctrl+C stops the API and web runner it started and retains database data.

`setup` installs backend dependencies and refreshes the host Flutter test runner plus web artifacts. It creates a private `backend/.env` only when one does not exist. It preserves existing settings and database volumes. If an existing `.env` has a blank or different database password, set it to the password used when that PostgreSQL volume was initialized; the launcher reports that problem without resetting data. You only need `create-admin` for your first administrator.

The launcher resolves project directories itself. It works from `backend` too: `python3 ../scripts/local.py run`. For ports already in use, choose `--api-port 18000 --web-port 18090`. The public GitHub Pages address is a separate deployment and cannot connect to PostgreSQL on your laptop.

### Repair the errors from the macOS log

- **Missing `darwin-x64/flutter_tester`:** run `python3 scripts/local.py repair-flutter`. This runs `flutter precache --universal --web --force` and frozen dependency resolution. A web build can pass even when the host binary required for widget tests is missing. Keep the Flutter installation native to your machine's architecture; do not copy another machine's Flutter cache.
- **Connection refused on `127.0.0.1:5432`:** open Docker Desktop, wait for its engine, and run `python3 scripts/local.py database`. This starts PostgreSQL before applying migrations. `alembic check` checks an already running, migrated database; it does not start PostgreSQL.
- **`cd: no such file or directory: frontend` / missing `pubspec.yaml`:** the shell was already in `backend`. Use the launcher from the repository root, or `python3 ../scripts/local.py check` from `backend`, instead of copying commands that assume another directory.
- **Newer dependencies available / tree-shaken fonts / Wasm dry run:** these are informational messages. They did not cause the logged failures. Keep the committed lockfile; upgrading every package is not the repair.
- **“The live academy server has not been connected” on GitHub Pages:** configure a public HTTPS API using the deployment steps below. Local debug runs default to `http://127.0.0.1:8000`, and the launcher sets it explicitly. Published builds require `ACADEMY_API_BASE_URL`; GitHub Pages hosts the frontend only.

To run the complete local checks with the database prepared:

```bash
python3 scripts/local.py check
```

## Run the website

Use Flutter **3.47.8** (Dart 3.13.7), matching CI. The project supports web; native mobile platform projects are not included.

```bash
cd frontend
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8090
```

For a GitHub Pages release:

```bash
flutter build web --release --base-href /Al_hassan-quran-acedemy/ --no-web-resources-cdn
```

This creates `frontend/build/web`. Fonts and renderer files are served with the website. Google Fonts runtime requests are unnecessary; font licenses are included in `frontend/assets/fonts`.

To connect a live backend during local web development:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8090 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Only debug builds accept localhost HTTP. Published builds require an HTTPS API URL. The base URL has no `/api` suffix. The client appends it. A missing server leaves the public demo available and explains that live sign-in is unavailable.

## Run the backend

Prerequisites: Python 3.12 and Docker Compose. From the repository root:

```bash
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements-dev.txt
cp backend/.env.example backend/.env
```

Edit the ignored `backend/.env` on your own machine, supplying a strong database password. Do not commit it. For local frontend development, add `http://127.0.0.1:8090` to the comma-separated `ACADEMY_ORIGINS` list. Origins contain no trailing slash or URL path.

Start PostgreSQL using the **same** database password in your shell's `POSTGRES_PASSWORD` variable:

```bash
docker compose -f infra/compose.yaml up -d --wait
cd backend
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m app.manage create-admin
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

The admin command prompts for a name, email and password; there are no default production credentials. Sign in as that administrator, create student/teacher/parent accounts under People, and link them under Assignments before scheduling classes. Each student's access must be linked to the teacher who teaches the class.

`GET /health`, `GET /health/db`, and `/docs` describe and check the service. API routes use the `/api` prefix. PostgreSQL stays bound to `127.0.0.1:5432`.

## Publish through GitHub Pages

1. The repository owner must open **Settings → Pages** and set **Source → GitHub Actions**. Keep the existing repository name to use the target URL above. The connected GitHub integration can push this project, but cannot enable Pages itself.
2. Push this project to `main`. `.github/workflows/pages.yml` analyzes and tests Flutter, checks the backend with SQLite and PostgreSQL, builds the website with its repository base path, and deploys the website when checks pass.
3. For live sign-in, first deploy the backend separately over HTTPS, then add the non-secret repository variable `ACADEMY_API_BASE_URL`, for example `https://api.your-academy-domain.com`. Rerun the Pages workflow. Leave it empty for the public demo.
4. On the backend, allow the origin `https://arshadqais.github.io` through `ACADEMY_ORIGINS`. Never put database passwords, session tokens, or LiveKit secrets in a frontend build or repository variable.

If the first deployment ran before Pages was enabled, rerun the failed deployment job or run the workflow manually after enabling it.

The API, database and GitHub Pages have separate lifecycles. Deploying the website does not update a Python process on the academy server. See [server deployment and backups](docs/deployment.md).

See [new modules and usage](docs/academy-modules.md) for weekly schedules, family records, attendance charts, administrator chat review, and screen-share highlights.

## Validation

From the repository root:

```bash
python3 scripts/local.py check
python3 -m unittest discover -s scripts/tests -v
```

If your terminal is already in `backend`, use `python3 ../scripts/local.py check`. The launcher handles all working directories, host Flutter artifacts, PostgreSQL readiness, migrations, frontend analysis/tests/build, and backend tests. Do not run Flutter commands from the backend folder.

The backend suite defaults to an isolated, in-memory SQLite database. It can also use an isolated PostgreSQL database via `ACADEMY_TEST_DATABASE_URL`; its database name must end with `_test`. Tests delete and recreate academy tables in that test database. Never point tests at a real academy database.

The backend tests cover role/record ownership, private conversations, sessions, rate limiting, password revocation, scheduling, enrollment, homework, feedback, attendance, and short-lived room grants. Frontend tests cover four demo portals, mobile navigation, record creation, progress updates, homework, messages, parent-child switching, and the live authentication client.

## Pilot boundaries

This is a working development pilot, not a completed production rollout. The repository does not yet include file uploads, email invitations/recovery, explicit parent consent to read child-teacher conversations, or native mobile apps. Study notes and persisted text messages are supported. Private conversations are visible only to their participants; the app does not silently grant parents or administrators access to other people's conversations.

A real LiveKit call, HTTPS tunnel, off-machine backup destination, and public GitHub Pages deployment need the academy's hosting and service access. The video client and token authorization can be built/tested independently, but an actual two-person media call must be validated using the chosen provider before teaching real learners. No real student records were used in development.
