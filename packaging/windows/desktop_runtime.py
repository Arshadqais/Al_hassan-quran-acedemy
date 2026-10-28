"""Client-owned PostgreSQL lifecycle. No developer database or credentials bundled."""
from __future__ import annotations
import csv
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from dotenv import dotenv_values, set_key

API_PORT = 18080
PG_PORT = 15432


class DesktopError(RuntimeError):
    def __init__(self, message, diagnostics=""):
        super().__init__(message)
        self.diagnostics = diagnostics


def windows_flags():
    return getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0


def run(command, *, env=None, timeout=120, check=True, input_text=None):
    # PostgreSQL's Windows background child can inherit output handles. Files
    # let us wait for the command itself without waiting for pipe EOF from a
    # long-running server. Output remains private and is read only on completion.
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as output, \
            tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as errors:
        process = subprocess.Popen([str(v) for v in command], env=env,
            stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
            text=True, stdout=output, stderr=errors, creationflags=windows_flags())
        timed_out = None
        try:
            process.communicate(input=input_text, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            timed_out = exc
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    capture_output=True, timeout=15, creationflags=windows_flags())
            else:
                process.kill()
            process.wait(timeout=10)
        output.seek(0)
        errors.seek(0)
        stdout, stderr = output.read(), errors.read()
        if timed_out:
            raise DesktopError(f"{Path(str(command[0])).name} timed out. Startup was stopped.",
                f"{stdout}\n{stderr}") from timed_out
        result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    if check and result.returncode:
        raise DesktopError(f"{Path(str(command[0])).name} could not complete. Check the private log folder or contact your developer.",
            f"Exit code: {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result


def restrict_directory(path: Path):
    path.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        identity = run(["whoami", "/user", "/fo", "csv", "/nh"]).stdout
        row = next(csv.reader([identity.strip()]))
        sid = row[-1]
        if not sid.startswith("S-1-"):
            raise DesktopError("Could not identify the Windows account for private data permissions.")
        run(["icacls", path, "/inheritance:r", "/grant:r", f"*{sid}:(OI)(CI)F",
            "/grant:r", "*S-1-5-18:(OI)(CI)F"])
    else:
        path.chmod(0o700)


def port_in_use(port):
    with socket.socket() as s:
        s.settimeout(.5)
        return s.connect_ex(("127.0.0.1", int(port))) == 0


class DesktopRuntime:
    def __init__(self, app_dir: Path, data_dir: Path):
        self.app_dir, self.data_dir = app_dir.resolve(), data_dir.resolve()
        if self.app_dir == self.data_dir or self.app_dir in self.data_dir.parents:
            raise DesktopError("Database storage must be outside the application installation folder.")
        self.env_file = self.data_dir / "backend.env"
        self.cluster = self.data_dir / "postgres"
        self.backups = self.data_dir / "backups"
        self.logs = self.data_dir / "logs"
        self.pg_bin = self.app_dir / "postgres" / "bin"
        self.service = self.app_dir / "service" / "AlHassanService.exe"
        self.frontend = self.app_dir / "desktop" / "AlHassanAcademy.exe"
        self.api_process = None
        self.frontend_processes = []
        self.api_log = None
        self.pg_started = False

    def initialize(self):
        restrict_directory(self.data_dir)
        for directory in [self.backups, self.logs]:
            directory.mkdir(exist_ok=True)
        if not self.env_file.exists():
            text = (f"DATABASE_USER=academy\nDATABASE_PASSWORD={secrets.token_hex(32)}\n"
                f"DATABASE_HOST=127.0.0.1\nDATABASE_PORT={PG_PORT}\nDATABASE_NAME=quran_academy\n"
                "ACADEMY_ORIGINS=https://arshadqais.github.io\n")
            with self.env_file.open("x", encoding="utf-8") as f:
                f.write(text)
            if os.name != "nt":
                self.env_file.chmod(0o600)
        self.config = dict(dotenv_values(self.env_file))
        if (self.config.get("DATABASE_URL") or self.config.get("DATABASE_HOST") != "127.0.0.1"
            or self.config.get("DATABASE_USER") != "academy" or self.config.get("DATABASE_NAME") != "quran_academy"
            or not self.config.get("DATABASE_PASSWORD")):
            raise DesktopError("The desktop edition needs its own local database configuration. Existing settings were not changed.")
        port = int(self.config.get("DATABASE_PORT", PG_PORT))
        if not 1024 <= port <= 65535:
            raise DesktopError("Invalid local database port.")
        return self.config

    def process_env(self):
        # Do not accidentally inherit a developer's database/provider overrides.
        values = {k: v for k, v in os.environ.items() if not k.startswith(
            ("DATABASE_", "LIVEKIT_", "WHATSAPP_", "ACADEMY_", "REMINDER_", "PG"))}
        values.update(ACADEMY_ENV_FILE=str(self.env_file), ACADEMY_DATA_DIR=str(self.data_dir),
            PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
        return values

    def pg_env(self):
        values = self.process_env()
        values["PGPASSWORD"] = self.config["DATABASE_PASSWORD"]
        return values

    def pg(self, name):
        return self.pg_bin / (name + ".exe")

    def start_postgres(self):
        if self.cluster.exists() and any(self.cluster.iterdir()) and not (self.cluster / "PG_VERSION").exists():
            raise DesktopError("The database directory contains existing files but is not a recognized cluster. No files were removed.")
        if not (self.cluster / "PG_VERSION").exists():
            self.cluster.mkdir(exist_ok=True)
            fd, filename = tempfile.mkstemp(prefix=".initial-password-", dir=self.data_dir)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(self.config["DATABASE_PASSWORD"])
                run([self.pg("initdb"), "-D", self.cluster, "-U", "academy", "--encoding=UTF8",
                    "--locale=C", "--auth-host=scram-sha-256", "--auth-local=scram-sha-256",
                    "--pwfile=" + filename], env=self.process_env())
            finally:
                Path(filename).unlink(missing_ok=True)
        if (self.cluster / "PG_VERSION").read_text().strip() != "17":
            raise DesktopError("This installer supports PostgreSQL 17 data. A database major-version upgrade needs a separate migration.")
        status = run([self.pg("pg_ctl"), "status", "-D", self.cluster], check=False)
        if status.returncode != 0:
            if port_in_use(self.config["DATABASE_PORT"]):
                raise DesktopError("The configured local database port is already used by another program. No existing service was stopped.")
            options = f"-h 127.0.0.1 -p {int(self.config['DATABASE_PORT'])} -c password_encryption=scram-sha-256"
            run([self.pg("pg_ctl"), "start", "-D", self.cluster, "-w", "-t", "60", "-l",
                self.logs / "postgres.log", "-o", options], env=self.process_env())
        self.pg_started = True
        exists = run([self.pg("psql"), "--no-password", "-h", "127.0.0.1", "-p", self.config["DATABASE_PORT"],
            "-U", "academy", "-d", "postgres", "-tAc",
            "SELECT 1 FROM pg_database WHERE datname='quran_academy'"], env=self.pg_env()).stdout.strip()
        if exists != "1":
            run([self.pg("createdb"), "--no-password", "-h", "127.0.0.1", "-p", self.config["DATABASE_PORT"],
                "-U", "academy", "quran_academy"], env=self.pg_env())

    def backup(self):
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = self.backups / (f"academy-{stamp}.dump")
        partial = path.with_suffix(".partial")
        try:
            run([self.pg("pg_dump"), "--no-password", "-h", "127.0.0.1", "-p", self.config["DATABASE_PORT"],
                "-U", "academy", "-d", "quran_academy", "-Fc", "--file", partial], env=self.pg_env())
            if not partial.exists() or partial.stat().st_size == 0:
                raise DesktopError("The database backup was not completed. Update cancelled.")
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
        return path

    def helper(self, action, payload=None, timeout=120):
        result = run([self.service, action], env=self.process_env(), check=False,
            input_text=json.dumps(payload or {}), timeout=timeout)
        try:
            data = json.loads(result.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            raise DesktopError("The packaged backend could not complete this operation. Check the private log folder.") from None
        if result.returncode or not data.get("ok"):
            raise DesktopError(data.get("error", "Backend operation failed."))
        return data

    def migrate(self):
        manifest = json.loads((self.app_dir / "build.json").read_text(encoding="utf-8"))
        marker = self.data_dir / "installed-build.json"
        previous = json.loads(marker.read_text()) if marker.exists() else None
        if previous and previous.get("commit") != manifest["commit"]:
            self.backup()  # Must succeed before applying an update's migration.
        self.helper("migrate")
        temporary = marker.with_suffix(".tmp")
        temporary.write_text(json.dumps(manifest), encoding="utf-8")
        temporary.replace(marker)

    def prepare(self):
        self.initialize()
        self.start_postgres()
        self.migrate()
        return self.helper("has-admin")["exists"]

    def start_api(self):
        if self.api_process is not None and self.api_process.poll() is None:
            return
        if port_in_use(API_PORT):
            raise DesktopError("Academy port 18080 is already in use. Close the other academy instance or contact support.")
        self.api_log = (self.logs / "backend.log").open("a", encoding="utf-8")
        self.api_process = subprocess.Popen([str(self.service), "serve"], env=self.process_env(),
            stdout=self.api_log, stderr=subprocess.STDOUT, creationflags=windows_flags())
        import urllib.request
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if self.api_process.poll() is not None:
                raise DesktopError("The academy backend stopped. Check the private backend log.")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{API_PORT}/health/db", timeout=2) as response:
                    if response.status == 200:
                        return
            except (OSError, ValueError):
                pass
            time.sleep(.25)
        raise DesktopError("The backend did not become ready. Existing database files were preserved.")

    def open_app(self):
        self.frontend_processes = [p for p in self.frontend_processes if p.poll() is None]
        if not self.frontend_processes:
            self.frontend_processes.append(subprocess.Popen([str(self.frontend)], creationflags=windows_flags()))

    def stop_api(self):
        if self.api_process is not None and self.api_process.poll() is None:
            # Uvicorn receives a console control event only in a console group;
            # terminate ends this owned process, never another local service.
            self.api_process.terminate()
            try:
                self.api_process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.api_process.kill()
                self.api_process.wait(timeout=5)
        self.api_process = None
        if self.api_log:
            self.api_log.close()
            self.api_log = None

    def restart_api(self):
        self.stop_api()
        self.start_api()

    def stop(self):
        self.stop_api()
        for p in self.frontend_processes:
            if p.poll() is None:
                p.terminate()
        if self.pg_started:
            run([self.pg("pg_ctl"), "stop", "-D", self.cluster, "-m", "fast", "-w", "-t", "30"],
                env=self.process_env(), check=True)
            self.pg_started = False
