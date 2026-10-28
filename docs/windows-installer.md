# Windows admin-computer installer

This package is for the **client administrator's host computer**. It includes a
native Flutter Windows app, a frozen Python/FastAPI backend, and PostgreSQL 17.
The client does not install Git, Python, Flutter, Docker, or a browser for the
local native app. Other students/teachers/parents use the academy website once
public HTTPS access to this host's backend has been configured separately.

The installer/build pipeline is a preview until the Windows workflow and a real
client hardware acceptance test pass. Do not describe a source commit alone as
a successfully tested downloadable installer. The initial pipeline creates a
GitHub Actions artifact, not a public GitHub Release automatically.

## 1. Build and obtain the installer (developer)

Push the packaging changes to `main`, or open **Actions → Build Windows client
installer → Run workflow** and specify a version such as `0.1.0`. The workflow:

1. Uses the pinned Flutter SDK and builds `AlHassanAcademy.exe` for Windows x64.
2. Packages the backend and its Python runtime using PyInstaller.
3. Copies only PostgreSQL 17 program binaries/libraries/share files, never the
   build machine's PostgreSQL data or passwords.
4. Includes app-local MSVC runtime files and dependency/license notices.
5. Builds `AlHassanAcademy-Setup-VERSION-windows-x64.exe` with Inno Setup.
6. Installs it on the Windows runner with isolated test data, initializes the
   database, creates a test admin, signs in, starts the native Flutter process,
   reinstalls, checks a pre-update backup and preserved records, and uninstalls
   while checking that client data remains.
7. Uploads the installer, SHA-256 checksum, and `windows-smoke-result.json` only
   after those checks pass.

Download the **AlHassanAcademy-Windows-x64** artifact from the successful run and
extract the installer. Artifacts are retained for 30 days and may require a
GitHub sign-in. Send the actual installer/checksum privately to the client, or
publish the verified artifact as a GitHub Release when ready. Building and
publishing from your Mac uses GitHub's Windows runner; it does not use your Mac
as the live academy server.

Local developer build on a prepared Windows build machine:

```powershell
./packaging/windows/build.ps1 -Version 0.1.0
```

Build-machine tools are not client requirements. The output is unsigned unless
you add your own trusted code-signing process. Windows may display an unknown
publisher prompt. Do not disable Windows security checks; verify the file source
and checksum and complete the client's normal software approval process.

## 2. Client installs

Use Windows 10 22H2/Windows 11 x64 with enough local disk space for the bundled
runtime, academy records, backups, and cached Quran. Windows on ARM and other
platforms are not part of the initial physical acceptance coverage.

1. Close any running Al Hassan Academy app/server before installing an update.
2. Double-click the installer and click Install. It installs for the current
   Windows user without requiring developer tooling.
3. Open the **Al Hassan Academy** desktop shortcut.
4. On first launch, the server window initializes a private local PostgreSQL
   cluster, generates a database password, and applies migrations.
5. Enter the first administrator's name, email, and a matching 12–128 character
   password in the setup form. No default admin password is supplied.
6. The native Flutter app opens. Click Academy sign in and use that account.

The small **Client Server** window stays in the taskbar. Keep it running or
minimized for backend access and WhatsApp reminders. Closing the Flutter window
does not stop the server. **Stop academy and exit** shuts down the owned backend
and PostgreSQL processes without deleting the database. This first version does
not install an always-on Windows service or start before the user signs in.

## 3. Where client data lives

Program files:

```text
%LOCALAPPDATA%\Programs\AlHassanAcademy
```

Private client data (outside the replaceable program folder):

```text
%LOCALAPPDATA%\AlHassanAcademy\
  backend.env          private client database/provider settings
  postgres\            PostgreSQL 17 data cluster
  backups\             local PostgreSQL custom-format dumps
  quran\               cached public Quran editions
  logs\                local runtime logs
  installed-build.json applied application build
```

The launcher restricts this folder to the current Windows account and SYSTEM.
Database credentials are generated on that machine and passed to database tools
through process configuration, never command-line passwords. A developer's
`DATABASE_URL` or provider environment overrides are not inherited by the
packaged backend. It binds PostgreSQL to loopback port 15432 and FastAPI to
loopback port 18080. Port conflicts are reported instead of taking over another
service or deleting another database.

This does not transfer data from an existing Mac automatically. Any real record
migration needs a separate, verified database backup/restore handover before the
old live installation is removed. Keep a preserved source backup and verify
accounts/attendance/progress/chat on the client computer before retiring it.

## 4. Optional services

From the client server window:

- **Configure video calls:** enter LiveKit WSS URL, API key, and secret privately.
  The backend verifies credentials and restarts after saving.
- **Configure WhatsApp reminders:** enter the client's business sender/token and
  approved template settings. Verification sends no WhatsApp message. See the
  [WhatsApp guide](whatsapp-reminders.md). Recipients still need to opt in.
- **Download / refresh Quran library:** download Arabic, Urdu, and English
  editions to the client's cache. This needs initial internet access; a failure
  does not replace valid cached scripture.
- **Back up database:** create a private local dump. Keep an additional secure
  copy under the client's control; uninstall does not export it automatically.

Native Windows screen sharing opens a screen/window picker. Camera, microphone,
video calls, screen capture, and rectangle highlights still need testing with
the actual client hardware and LiveKit service. Provider accounts should belong
to the client, with secrets entered on the client machine.

## 5. Future changes and updates

Develop and test on your Mac with a separate development database. Push code,
build a new Windows installer, and deliver it to the client. Run the new installer
over the previous installation using the same Windows account. The persistent
AppId retains the install location and shortcuts; uninstall never deletes the
separate data folder.

On the next launch after a changed build, the launcher makes a PostgreSQL dump
before applying migrations. A failed backup blocks the migration; a failed
migration does not advance the applied-build marker. The program does not reset
users, attendance, chat, or settings. Do not change PostgreSQL major versions in
this update path: the launcher deliberately refuses non-17 clusters. Major
version upgrades and database restoration are separate reviewed operations.

Updates are manually installed in this first version. A GitHub push does not
silently change the client's computer or upload their database. An unattended
updater, signed-release channel, Windows service deployment, and remote HTTPS
hosting are separate future steps.
