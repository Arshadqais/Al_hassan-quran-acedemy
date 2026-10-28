"""Windows CI installation/update preservation check, always using isolated data."""
from datetime import date
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parent))
from desktop_runtime import DesktopRuntime, API_PORT


def request(path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(f"http://127.0.0.1:{API_PORT}/api{path}",
        data=json.dumps(body).encode() if body is not None else None, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response) if response.status != 204 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("installer", type=Path)
    args = parser.parse_args()
    if os.name != "nt" or not os.environ.get("RUNNER_TEMP"):
        raise SystemExit("Run this isolated install smoke test on a Windows CI runner.")
    base = Path(tempfile.mkdtemp(prefix="academy-installer-", dir=os.environ["RUNNER_TEMP"]))
    install, data = base / "program", base / "client-data"
    subprocess.run([str(args.installer.resolve()), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", f"/DIR={install}"], check=True)
    runtime = DesktopRuntime(install, data)
    frontend = None
    try:
        assert runtime.prepare() is False
        runtime.helper("create-admin", {"name": "CI administrator", "email": "installer@example.test", "password": "Test-only-installer-credential-879!"})
        runtime.start_api()
        token = request("/auth/login", {"email": "installer@example.test", "password": "Test-only-installer-credential-879!"})["token"]
        user = request("/users", {"name": "Preserved student", "email": "preserved@example.test", "password": "Test-only-learner-credential-879!", "role": "student"}, token)
        assert user["name"] == "Preserved student"
        teacher = request("/users", {"name": "CI teacher", "email": "teacher@example.test", "password": "Test-only-teacher-credential-879!", "role": "teacher"}, token)
        request("/assignments", {"adult_id": teacher["id"], "student_id": user["id"]}, token)
        request("/schedules", {"title": "Client timezone check", "teacher_id": teacher["id"], "student_ids": [user["id"]],
            "start_date": date.today().isoformat(), "weekdays": [0,1,2,3,4], "local_time": "09:00", "timezone": "Asia/Karachi"}, token)
        assert len(request("/classes", token=token)) > 1, "Bundled timezone data/recurrence must work on Windows"
        frontend = subprocess.Popen([str(runtime.frontend)], env=runtime.process_env())
        time.sleep(8)
        assert frontend.poll() is None, "Native Flutter window exited during startup"
        frontend.terminate(); frontend.wait(timeout=10); frontend = None
        runtime.stop()
        # Simulate a previous application build, then reinstall and run migration.
        marker = data / "installed-build.json"
        old = json.loads(marker.read_text()); old["commit"] = "ci-previous-build"
        marker.write_text(json.dumps(old))
        subprocess.run([str(args.installer.resolve()), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", f"/DIR={install}"], check=True)
        runtime = DesktopRuntime(install, data)
        assert runtime.prepare() is True
        assert list((data / "backups").glob("*.dump")), "Update must back up before migrations"
        runtime.start_api()
        token = request("/auth/login", {"email": "installer@example.test", "password": "Test-only-installer-credential-879!"})["token"]
        assert any(u["email"] == "preserved@example.test" for u in request("/users", token=token))
        runtime.stop()
        subprocess.run([str(install / "unins000.exe"), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"], check=True)
        assert (data / "postgres" / "PG_VERSION").exists()
        assert (data / "backend.env").exists()
        report = {"installation": "passed", "postgresql": "client-local", "admin_sign_in": "passed",
            "native_flutter_start": "passed", "packaged_timezone_and_recurrence": "passed", "update_backup": "passed", "records_preserved": "passed",
            "uninstall_keeps_data": "passed", "scope": "Windows CI; real client hardware still requires acceptance testing"}
        (args.installer.parent / "windows-smoke-result.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
    finally:
        if frontend and frontend.poll() is None:
            frontend.terminate()
        runtime.stop()


if __name__ == "__main__":
    main()
