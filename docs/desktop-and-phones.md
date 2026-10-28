# Use the academy on desktop, Android, and iPhone

The administrator's Windows PC runs the native desktop app, FastAPI, and
PostgreSQL. Teachers, students, and parents can install the academy website on
their phones. Everyone uses the same academy accounts and records; the phone
installation does not create another database or copy the developer's database.

## Administrator setup

1. Install the [Windows preview](https://github.com/Arshadqais/Al_hassan-quran-acedemy/releases/tag/windows-preview-0.1.0-af76ab5)
   on the client's Windows PC and create the first admin account.
2. Keep its Client Server window running. The PC must stay on, connected to the
   internet, and awake while remote users need lessons, chat, or records.
3. Configure a stable, valid HTTPS API address using an authenticated reverse
   proxy or Cloudflare Tunnel on **that Windows PC**, pointing to
   `http://127.0.0.1:18080`. The database port must stay private. Do not use the
   developer's Mac, `localhost`, or `127.0.0.1` as the phone's API address.
4. Set the repository variable `ACADEMY_API_BASE_URL` to that public HTTPS API
   address, with no `/api` suffix. Redeploy the **Test and deploy academy website**
   workflow. The desktop package already allows the academy's GitHub Pages
   origin; a different website domain also needs the client's origins setting.
5. Verify `/health/db` externally and sign in with separate test teacher, student,
   and parent accounts from a phone on mobile data before inviting real users.
   Configure the client's LiveKit project privately for real video classes.

The installer does not configure the tunnel, a domain, or GitHub variables
automatically. Until the public API is connected, installing the website can
still show the public/demo interface but does not make real accounts available.

## Install on Android

1. Open [Al Hassan Academy](https://arshadqais.github.io/Al_hassan-quran-acedemy/)
   in Chrome, rather than an embedded WhatsApp browser.
2. Open Chrome's three-dot menu and choose **Install app** or **Add to Home screen**.
3. Confirm the installation, open the Al Hassan icon, and sign in with the
   academy-issued account. Menu wording varies by Android/Chrome version.

## Install on iPhone or iPad

1. Open the same academy link in Safari.
2. Tap **Share**, then **Add to Home Screen**. Scroll the actions list if needed.
3. Keep **Open as Web App** enabled if offered, then tap **Add**.
4. Open the Al Hassan icon and sign in. Safari and the installed web app may
   maintain separate sessions, so a fresh sign-in can be necessary.

## Other desktop users

Chrome and Edge can install the same website using the address-bar install icon
or the browser's app installation menu. This is a client for the existing
academy; it does not run a second PostgreSQL server. Only the administrator's
host PC needs the native Windows server installer.

## Connectivity, privacy, and updates

Internet access and the admin server are required for records, Quran downloads,
chat, and classes. The service worker caches only a public offline notice. It
does not cache private API responses, classroom tokens, attendance, or messages,
and it does not queue writes while offline. Reconnecting loads the current
website; application updates are published from the developer's checkout to
GitHub Pages. Backend changes still require a new installer on the admin PC.

Allow microphone/camera access when joining a class. Phone users can view the
teacher's shared screen and highlights. Most mobile browsers cannot publish the
phone's own screen; teachers should share from desktop. Real Android Chrome and
iPhone Safari installation, camera/microphone, background/resume behavior, and
LiveKit calls still need acceptance testing on the intended devices. An installed
website does not imply App Store/Play Store publication or push notifications.

Developer builds must use `flutter build web --release --pwa-strategy=none`
with the correct `--base-href` and HTTPS `API_BASE_URL`. The academy's own service
worker provides the offline notice; Flutter's generated app-cache worker must
not compete for the same scope.

To repeat browser checks after serving that build, install Playwright on the
developer machine and run `python3 scripts/check_mobile_web.py --url URL
--output-dir /tmp/academy-pwa-check`. Use `--browser-executable /path/to/chromium`
for an existing Chromium installation, or install Playwright's Chromium first.
The check uses disposable non-incognito profiles, validates desktop/phone
installation eligibility and icons, exercises the install dialog and offline
reconnection, and verifies that Cache Storage contains only the public notice.
