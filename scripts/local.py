#!/usr/bin/env python3
"""Start the local academy from any working directory. Never resets database data."""

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
import threading
import webbrowser
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
FRONTEND = ROOT / "frontend"
PYTHON = BACKEND / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
ENV_FILE = BACKEND / ".env"


class LocalError(Exception):
    pass


def run(args, *, cwd=ROOT, env=None, capture=False):
    result = subprocess.run(
        [str(a) for a in args], cwd=cwd, env=env, text=True, capture_output=capture
    )
    if result.returncode:
        raise LocalError(
            f"{Path(str(args[0])).name} command failed. Resolve the error above before continuing."
            if not capture
            else "Prerequisite check failed."
        )
    return result.stdout if capture else None


def flutter():
    executable = shutil.which("flutter")
    if not executable:
        raise LocalError(
            "Flutter is not on PATH. Install Flutter 3.47.8 and add its bin directory to PATH."
        )
    return executable


def require_python():
    if not PYTHON.exists():
        raise LocalError(
            "Backend dependencies are not installed. Run: python3 scripts/local.py setup"
        )


def settings():
    require_python()
    # Read dotenv through the project's installed parser; capture values privately.
    output = run(
        [
            PYTHON,
            "-c",
            'import json; from dotenv import dotenv_values; print(json.dumps(dotenv_values(".env")))',
        ],
        cwd=BACKEND,
        capture=True,
    )
    values = json.loads(output)
    return {
        **values,
        **{
            k: v
            for k, v in os.environ.items()
            if k.startswith(("DATABASE_", "LIVEKIT_")) or k == "ACADEMY_ORIGINS"
        },
    }


def initialize_env():
    if ENV_FILE.exists():
        print("Keeping your existing backend/.env unchanged.")
        return
    content = (
        "DATABASE_USER=academy\nDATABASE_PASSWORD="
        + secrets.token_hex(32)
        + "\nDATABASE_HOST=127.0.0.1\nDATABASE_PORT=5432\nDATABASE_NAME=quran_academy\n"
        "ACADEMY_ORIGINS=http://127.0.0.1:8090,http://localhost:8090\n"
    )
    # Exclusive creation prevents overwriting another setup process or user file.
    with ENV_FILE.open("x", encoding="utf-8") as handle:
        handle.write(content)
    ENV_FILE.chmod(0o600)
    print("Created private backend/.env with a generated local database password.")


def repair_flutter(force=False):
    args = [flutter(), "--suppress-analytics", "precache", "--universal", "--web"]
    if force:
        args.append("--force")
    run(args, cwd=FRONTEND)
    run(
        [flutter(), "--suppress-analytics", "pub", "get", "--enforce-lockfile"],
        cwd=FRONTEND,
    )


def setup():
    if sys.version_info < (3, 12):
        raise LocalError(
            "Use Python 3.12 or newer. Python 3.12 is the version used in CI."
        )
    if not PYTHON.exists():
        interpreter = shutil.which("python3.12") or sys.executable
        run([interpreter, "-m", "venv", BACKEND / ".venv"])
    run([PYTHON, "-m", "pip", "install", "-r", BACKEND / "requirements-dev.txt"])
    initialize_env()
    # Host test artifacts are needed in addition to web artifacts. Force refresh
    # repairs stale SDK cache stamps when flutter_tester was not downloaded.
    repair_flutter(force=True)
    print("\nSetup complete. Next: python3 scripts/local.py create-admin")
    print("Then start both services: python3 scripts/local.py run")


def database():
    config = settings()
    if not config.get("DATABASE_URL") and config.get("DATABASE_HOST", "127.0.0.1") in (
        "127.0.0.1",
        "localhost",
    ):
        if not config.get("DATABASE_PASSWORD"):
            raise LocalError(
                "DATABASE_PASSWORD is blank in backend/.env. Set it to the password for your local PostgreSQL database; existing settings and data have not been changed."
            )
        docker = shutil.which("docker")
        if not docker:
            raise LocalError(
                "Install Docker Desktop, open it, and wait until its engine is running. Then rerun this command."
            )
        try:
            run([docker, "info", "--format", "{{.ServerVersion}}"], capture=True)
        except LocalError:
            raise LocalError(
                "Docker is not running. Open Docker Desktop and wait for its engine, then rerun this command."
            ) from None
        process_env = os.environ.copy()
        process_env.update(
            {
                k: str(config[k])
                for k in ("DATABASE_USER", "DATABASE_NAME", "DATABASE_PORT")
                if config.get(k)
            }
        )
        process_env["POSTGRES_PASSWORD"] = config["DATABASE_PASSWORD"]
        run(
            [
                docker,
                "compose",
                "-f",
                ROOT / "infra/compose.yaml",
                "up",
                "-d",
                "--wait",
            ],
            env=process_env,
        )
    check = subprocess.run(
        [
            str(PYTHON),
            "-c",
            "import asyncio\nfrom app.db.database import check_database\n"
            "async def main():\n"
            " try:\n  ok=await check_database()\n"
            " except Exception:\n  raise SystemExit(1) from None\n"
            " if not ok: raise SystemExit(1)\n"
            "asyncio.run(main())",
        ],
        cwd=BACKEND,
        capture_output=True,
        text=True,
    )
    if check.returncode:
        raise LocalError(
            "PostgreSQL is unavailable or its credentials do not match backend/.env. Check DATABASE_HOST/PORT/USER/PASSWORD/NAME. If a Docker volume already exists, use its original credentials. Do not delete the volume to fix a login error."
        )
    run([PYTHON, "-m", "alembic", "upgrade", "head"], cwd=BACKEND)
    print("PostgreSQL is connected and migrations are up to date.")


def server_env(web_port):
    config = settings()
    origins = [
        o.strip() for o in (config.get("ACADEMY_ORIGINS") or "").split(",") if o.strip()
    ]
    origins += [
        f"http://127.0.0.1:{web_port}",
        f"http://localhost:{web_port}",
        "https://arshadqais.github.io",
    ]
    return {**os.environ, "ACADEMY_ORIGINS": ",".join(dict.fromkeys(origins))}


def require_free_port(port):
    try:
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", port))
    except OSError:
        raise LocalError(
            f"Port {port} is already in use. Stop that local service or choose --api-port / --web-port."
        ) from None


def api_command(port):
    return [
        str(PYTHON),
        "-m",
        "uvicorn",
        "app.main:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--ws-max-size",
        "4096",
    ]


def web_command(args):
    return [
        flutter(),
        "--suppress-analytics",
        "run",
        "-d",
        "web-server",
        "--no-web-resources-cdn",
        "--web-hostname",
        "127.0.0.1",
        "--web-port",
        str(args.web_port),
        f"--dart-define=API_BASE_URL=http://127.0.0.1:{args.api_port}",
    ]


def wait_for_backend(process, port, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise LocalError("The API stopped during startup. Check its output above.")
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/health/db", timeout=1
            ) as response:
                payload = json.load(response)
                if response.status == 200 and payload.get("connected") is True:
                    return
        except (OSError, urllib.error.URLError, ValueError):
            pass
        time.sleep(0.25)
    raise LocalError(
        "The API did not become ready within 30 seconds. Check its startup output."
    )


def open_local_browser(port, stopped):
    deadline = time.monotonic() + 120
    while not stopped.is_set() and time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}", timeout=2
            ) as response:
                if response.status == 200:
                    if not stopped.is_set():
                        webbrowser.open(f"http://127.0.0.1:{port}")
                    return
        except (OSError, ValueError):
            pass
        stopped.wait(0.5)


def start(args):
    database()
    require_free_port(args.api_port)
    require_free_port(args.web_port)
    executable = web_command(args)  # Check Flutter before starting an API process.
    process = subprocess.Popen(
        api_command(args.api_port), cwd=BACKEND, env=server_env(args.web_port)
    )
    stopped = threading.Event()
    try:
        wait_for_backend(process, args.api_port)
        print(
            f"\nOpen http://127.0.0.1:{args.web_port} in your browser and choose Academy sign in.",
            flush=True,
        )
        print(
            "This local website is connected to your local API. Ctrl+C stops the services started here.",
            flush=True,
        )
        if getattr(args, "open_browser", False):
            threading.Thread(
                target=open_local_browser, args=(args.web_port, stopped), daemon=True
            ).start()
        run(executable, cwd=FRONTEND)
    finally:
        stopped.set()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        print("Local API stopped. PostgreSQL data is retained.")


def check():
    require_python()
    database()
    repair_flutter()
    for command in (
        [flutter(), "--suppress-analytics", "analyze"],
        [flutter(), "--suppress-analytics", "test"],
        [
            flutter(),
            "--suppress-analytics",
            "build",
            "web",
            "--release",
            "--base-href",
            "/Al_hassan-quran-acedemy/",
            "--no-web-resources-cdn",
        ],
    ):
        run(command, cwd=FRONTEND)
    run([PYTHON, "-m", "pytest", "tests", "-q"], cwd=BACKEND)
    run([PYTHON, "-m", "alembic", "check"], cwd=BACKEND)


def connect_pages():
    from urllib.parse import urlparse
    from urllib.error import URLError

    gh = shutil.which("gh")
    if not gh:
        raise LocalError(
            "Install GitHub CLI (macOS: brew install gh), then sign in using gh auth login with your repository-owner account."
        )
    url = input("Public HTTPS API URL (no /api suffix): ").strip().rstrip("/")
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.query
        or parsed.fragment
    ):
        raise LocalError(
            "Enter a valid HTTPS API base URL without credentials or query parameters."
        )
    try:
        request = urllib.request.Request(
            url + "/health/db", headers={"Origin": "https://arshadqais.github.io"}
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
            if (
                not payload.get("connected")
                or response.headers.get("Access-Control-Allow-Origin")
                != "https://arshadqais.github.io"
            ):
                raise ValueError()
    except (OSError, URLError, ValueError):
        raise LocalError(
            "The public API is not healthy or does not allow the academy website origin. Keep the API and tunnel running, and include https://arshadqais.github.io in ACADEMY_ORIGINS in backend/.env, then restart the API."
        ) from None
    run(
        [
            gh,
            "variable",
            "set",
            "ACADEMY_API_BASE_URL",
            "--body",
            url,
            "--repo",
            "Arshadqais/Al_hassan-quran-acedemy",
        ]
    )
    run(
        [
            gh,
            "workflow",
            "run",
            "pages.yml",
            "--repo",
            "Arshadqais/Al_hassan-quran-acedemy",
        ]
    )
    print(
        "Website build requested with your public API URL. Check the GitHub Actions deployment result. Temporary tunnel URLs change after restart; use a named tunnel and an academy-owned domain for ongoing use."
    )


def guided_setup(args):
    setup()
    database()
    status = subprocess.run(
        [str(PYTHON), "-m", "app.integrations", "has-admin"], cwd=BACKEND
    )
    if status.returncode == 10:
        run([PYTHON, "-m", "app.manage", "create-admin"], cwd=BACKEND)
    elif status.returncode != 0:
        raise LocalError(
            "Could not check the administrator account. Existing accounts were not changed."
        )
    else:
        print("An administrator already exists; use your existing account.")
    pending = []
    try:
        run([PYTHON, "-m", "app.integrations", "download-quran"], cwd=BACKEND)
    except LocalError:
        pending.append(
            "Quran text download: retry download-quran when connected to the provider"
        )
    print(
        "Internet video requires your LiveKit project. Create one at https://cloud.livekit.io if needed. Enter its credentials only in this local terminal.",
        flush=True,
    )
    if input("Configure internet video now? [Y/n]: ").strip().lower() != "n":
        try:
            run([PYTHON, "-m", "app.integrations", "configure-video"], cwd=BACKEND)
        except LocalError:
            pending.append(
                "Video provider: rerun configure-video with valid project credentials"
            )
    else:
        pending.append(
            "Video provider: run configure-video before joining video classes"
        )
    if pending:
        print("Setup still needs:\n- " + "\n- ".join(pending), flush=True)
    print(
        "Starting the academy on your computer. For remote participants, keep a public HTTPS tunnel and your internet video project available.",
        flush=True,
    )
    (BACKEND / ".local").mkdir(exist_ok=True)
    (BACKEND / ".local" / "desktop-setup-v1").touch()
    start(args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=[
            "setup",
            "guided-setup",
            "desktop",
            "repair-flutter",
            "configure-video",
            "download-quran",
            "check-services",
            "share-api",
            "connect-pages",
            "database",
            "create-admin",
            "run",
            "backend",
            "web",
            "check",
        ],
    )
    parser.add_argument("--open-browser", action="store_true")
    parser.add_argument("--api-port", type=int, default=8000)
    parser.add_argument("--web-port", type=int, default=8090)
    args = parser.parse_args()
    if not all(1 <= p <= 65535 for p in [args.api_port, args.web_port]):
        parser.error("Ports must be between 1 and 65535.")
    try:
        if args.command == "setup":
            setup()
        elif args.command == "guided-setup":
            guided_setup(args)
        elif args.command == "desktop":
            args.open_browser = True
            if (BACKEND / ".local" / "desktop-setup-v1").exists():
                start(args)
            else:
                guided_setup(args)
        elif args.command == "repair-flutter":
            repair_flutter(force=True)
        elif args.command == "database":
            database()
        elif args.command == "create-admin":
            database()
            run([PYTHON, "-m", "app.manage", "create-admin"], cwd=BACKEND)
        elif args.command in ("configure-video", "download-quran", "check-services"):
            require_python()
            run([PYTHON, "-m", "app.integrations", args.command], cwd=BACKEND)
        elif args.command == "share-api":
            cloudflared = shutil.which("cloudflared")
            if not cloudflared:
                raise LocalError(
                    "Install the official Cloudflare Tunnel client. On macOS: brew install cloudflared. Then start the academy and rerun share-api."
                )
            print(
                "Keep the academy running in another terminal. This opens a temporary public HTTPS route to the API only, not PostgreSQL. Keep this terminal open. Copy its HTTPS URL into connect-pages.",
                flush=True,
            )
            run([cloudflared, "tunnel", "--url", f"http://127.0.0.1:{args.api_port}"])
        elif args.command == "connect-pages":
            connect_pages()
        elif args.command == "run":
            start(args)
        elif args.command == "backend":
            database()
            require_free_port(args.api_port)
            run(api_command(args.api_port), cwd=BACKEND, env=server_env(args.web_port))
        elif args.command == "web":
            require_free_port(args.web_port)
            run(web_command(args), cwd=FRONTEND)
        else:
            check()
    except LocalError as exc:
        print(f"\nLocal setup: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nStopped. Database data has not been removed.")
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
