# Laptop database, Quran, live chat, and internet classrooms

Academic records, passwords, messages, and progress are stored in PostgreSQL in Docker on the academy laptop. FastAPI runs on that same laptop. The Quran text cache is saved in `backend/.local/quran/` on that laptop. LiveKit carries real-time media between browsers; it is separate from the academic database.

This repository can configure and run those services locally. A cloud coding session cannot directly configure an unattached laptop, create your personal LiveKit account, or enter its credentials for you.

## Start on your Mac

Install/open Docker Desktop and have Python 3.12+ and Flutter 3.47.8 on PATH. Pull the updated project, then **double-click `Start Academy.command`**. You can also run:

```bash
cd ~/Desktop/Al_hassan-quran-acedemy
git pull origin main
python3 scripts/local.py desktop
```

On its first launch the wizard:

1. Installs dependencies and the correct Flutter host/web artifacts.
2. Keeps existing `.env` values and PostgreSQL volumes, starts PostgreSQL, and applies migrations.
3. Creates your first administrator interactively if none exists. Existing administrator accounts are retained.
4. Downloads and validates the complete Quran text and optional Urdu/English translations into the local cache.
5. Asks for your internet video project's credentials privately and checks provider authentication before saving them.
6. Starts FastAPI and Flutter, waits for readiness, and opens the local website.

If a provider is unavailable or you skip video setup, it explicitly reports the remaining setup. Core features can still run; that does not mean the unavailable integration is ready. Later launches use the saved core setup and start the app. Keep the terminal, Docker Desktop, and laptop running while teaching. Ctrl+C stops the processes started by the launcher and retains database data.

Use your administrator account under **Academy sign in**. Create teacher/student/parent accounts under People, then link them under Assignments. Schedule classes for the linked students with the correct local date and time. Do not use demo profiles as real accounts.

## Create and connect your LiveKit project

1. Visit https://cloud.livekit.io/ and sign in/create your own account.
2. Create a project for the academy. Select its data region and service plan yourself.
3. Open **Manage API keys** (or the project's Settings/API keys).
4. Find the project's **WebSocket URL**, beginning with `wss://`, and its **API key** and **API secret**. The project ID is a different identifier; the application needs the actual server URL.
5. Enter them only into the local wizard, or configure an already-installed project with:

```bash
python3 scripts/local.py configure-video
```

The key/secret prompts are hidden. They are verified against the provider and stored only in the ignored `backend/.env`, with private filesystem permissions. They are never put into the Flutter build or GitHub repository. Restart the academy after changing them.

No AI agent, telephony number, or recording service is required for teacher/student classroom calls. The app does not add recording controls or request microphone/camera access before the user enables media. A browser's camera, microphone and screen-recording permissions must be allowed by its operator.

## Remote students need a public HTTPS API

A browser on another person's device cannot reach `127.0.0.1` on the academy laptop. Keep PostgreSQL private on loopback. Expose only FastAPI through a secure HTTPS tunnel.

For a temporary test, install the official Cloudflare Tunnel client and GitHub CLI (if you use Homebrew: `brew install cloudflared gh`). Keep `python3 scripts/local.py desktop` or `run` open in terminal 1. In terminal 2:

```bash
python3 scripts/local.py share-api
```

Keep that terminal open. Cloudflared prints a temporary public HTTPS address for the local API. The default app launch allows the exact GitHub Pages origin `https://arshadqais.github.io` through CORS and WebSocket origin checks. Other origins require explicit configuration.

Sign GitHub CLI into an account allowed to manage repository variables (`gh auth login` on your own machine), then in terminal 3:

```bash
python3 scripts/local.py connect-pages
```

Paste the **public HTTPS API URL** when prompted. This checks database health and website-origin access, sets the public `ACADEMY_API_BASE_URL` repository variable, and starts the website deployment workflow. It does not send database or LiveKit credentials to GitHub. Confirm the Actions deployment passed before sharing the website with students.

Use https://arshadqais.github.io/Al_hassan-quran-acedemy/ for remote students once the connected build is deployed. Their assigned accounts and class schedules come from the laptop API. LiveKit Cloud carries their media without requiring PostgreSQL access from their browsers.

Temporary tunnel addresses change when the tunnel is restarted, so reconnect/redeploy the frontend after a change. For ongoing academy use, set up a named Cloudflare Tunnel with an academy-owned domain instead. Laptop sleep, shutdown, a stopped API/tunnel, or lost internet makes shared academic records unavailable. If the laptop cannot stay available, move the same backend/database to an always-on academy-controlled server.

## Quran reading

Choose **Quran** after signing in. Browse every para (1–30) or Surah (1–114); select Arabic only or Arabic with Urdu/English translation. Search operates within the selected passage.

Source API: `https://api.alquran.cloud/v1/quran/quran-uthmani`. Urdu uses `ur.jalandhry`, and English uses `en.sahih`. Arabic text is from the Tanzil Project, served by AlQuran Cloud. Source strings are kept unchanged. The application checks all 114 Surahs, 6,236 sequential ayahs, and all 30 para identifiers before accepting a book. It never invents scripture to fill a failed request.

Download or refresh missing editions explicitly:

```bash
python3 scripts/local.py download-quran
```

This requires internet access to `api.alquran.cloud` for the first download. Valid books are cached on the laptop, so later reading can use the cache if the upstream service is unavailable. A corrupt/incomplete file is not served. If this command fails, the reader reports the provider/cache problem and offers Retry.

Attribution and usage: [AlQuran Cloud](https://alquran.cloud/), [Tanzil Project text license](https://tanzil.net/docs/Text_License). Translations remain attributed to their respective translators. Cached Quran texts are public learning content; they are separate from private academic records.

## Chat and calls

Messages are persisted in PostgreSQL. A session-authenticated WebSocket sends participant-only change notifications, and the client retrieves authorized messages through the API. Session tokens are never put in WebSocket URLs. Connections automatically reconnect after interruptions, and logout/expiry is rechecked while a socket is open. Use one API worker until a shared notification broker is added.

During a video lesson, open **Private chat** in the classroom header. The call continues while you message an authorized academy contact. This is private contact messaging, not a group-wide classroom broadcast. Teachers/admins can share screens; student room tokens only permit camera and microphone. If browser autoplay blocks sound, use **Enable audio**. A revoked/expired academy session disconnects the classroom when detected by the live session check.

Before teaching real learners, test two actual devices on separate internet connections: sign in as an assigned teacher/student, join a currently scheduled class, enable camera and microphone, verify sound/video in both directions, share a screen, send chat while connected, and leave/rejoin. Simulated local media tests do not establish your internet connection, device permissions, provider account, or TURN/firewall readiness.

## Diagnose connections

```bash
python3 scripts/local.py check-services
```

This reports database connectivity, whether the Arabic cache exists, and whether the configured video provider actually authenticates. A saved video URL alone is not a successful provider test. Never paste `.env`, passwords, API secrets or session tokens into chat/logs.
