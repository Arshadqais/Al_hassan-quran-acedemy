"""Fast PostgreSQL portability check, restricted to disposable Windows CI storage."""
import os
from pathlib import Path
import shutil
import tempfile

from desktop_runtime import DesktopRuntime, restrict_directory


def main():
    if os.name != "nt" or not os.environ.get("RUNNER_TEMP"):
        raise RuntimeError("This probe is only for the isolated Windows build runner")
    root = Path(tempfile.mkdtemp(prefix="academy-pg-probe-", dir=os.environ["RUNNER_TEMP"]))
    app = root / "program"
    for name in ("bin", "lib", "share"):
        shutil.copytree(Path(r"C:\Program Files\PostgreSQL\17") / name, app / "postgres" / name)
    runtime = DesktopRuntime(app, root / "client-data")
    # GitHub's elevated runner temp tree can otherwise grant access only through
    # Administrators, which PostgreSQL deliberately removes from its token.
    restrict_directory(app)
    try:
        runtime.initialize()
        runtime.start_postgres()
        print("Portable PostgreSQL initialization and authenticated connection passed")
    except Exception as exc:
        details = str(exc) + "\n" + getattr(exc, "diagnostics", "")
        import pefile
        available = {p.name.lower(): p for p in (app / "postgres").rglob("*") if p.is_file()}
        checked = set()
        def dependencies(path):
            if path.name.lower() in checked:
                return
            checked.add(path.name.lower())
            with pefile.PE(str(path)) as binary:
                for entry in getattr(binary, "DIRECTORY_ENTRY_IMPORT", []):
                    name = entry.dll.decode().lower()
                    target = available.get(name)
                    findings.append(f"{path.name} imports {name}: {target or 'Windows system'}")
                    if target:
                        if target.parent != runtime.pg_bin:
                            findings.append(f"{path.name} needs {name} located in {target.parent}")
                        dependencies(target)
                    elif not name.startswith(("api-ms-", "ext-ms-")) and not (Path(os.environ["WINDIR"]) / "System32" / name).exists():
                        findings.append(f"{path.name} missing dependency: {name}")
        findings = []
        dependencies(runtime.pg("initdb"))
        dependencies(runtime.pg("postgres"))
        import subprocess
        import ctypes
        for executable in (Path(r"C:\Program Files\PostgreSQL\17\bin\initdb.exe"), runtime.pg("initdb")):
            result = subprocess.run([str(executable), "--version"], capture_output=True, text=True)
            findings.append(f"Version probe {executable}: {result.returncode} {result.stdout} {result.stderr}")
        with os.add_dll_directory(str(runtime.pg_bin)):
            for name in sorted(checked):
                target = available.get(name)
                if target and target.suffix == ".dll":
                    try:
                        ctypes.WinDLL(str(target))
                    except OSError as failure:
                        findings.append(f"LoadLibrary {name}: {failure}")
        details += "\n" + "\n".join(findings)
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
