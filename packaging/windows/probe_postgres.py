"""Fast PostgreSQL portability check, restricted to disposable Windows CI storage."""
import os
from pathlib import Path
import shutil
import tempfile

from desktop_runtime import DesktopRuntime


def main():
    if os.name != "nt" or not os.environ.get("RUNNER_TEMP"):
        raise RuntimeError("This probe is only for the isolated Windows build runner")
    root = Path(tempfile.mkdtemp(prefix="academy-pg-probe-", dir=os.environ["RUNNER_TEMP"]))
    app = root / "program"
    for name in ("bin", "lib", "share"):
        shutil.copytree(Path(r"C:\Program Files\PostgreSQL\17") / name, app / "postgres" / name)
    runtime = DesktopRuntime(app, root / "client-data")
    try:
        runtime.initialize()
        runtime.start_postgres()
        print("Portable PostgreSQL initialization and authenticated connection passed")
    except Exception as exc:
        details = str(exc) + "\n" + getattr(exc, "diagnostics", "")
        for key, value in getattr(runtime, "config", {}).items():
            if value and any(part in key for part in ("PASSWORD", "SECRET", "TOKEN")):
                details = details.replace(value, "[redacted]")
        Path(__file__).with_name("ci-diagnostics.txt").write_text(details, encoding="utf-8")
        print(details)
        raise
    finally:
        runtime.stop()


if __name__ == "__main__":
    main()
