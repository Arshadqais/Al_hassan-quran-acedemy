Native Flutter Windows **admin-host preview installer** with bundled FastAPI,
Python runtime, and PostgreSQL 17. The client does not install developer tools.

1. Download `AlHassanAcademy-Setup-…-windows-x64.exe` and verify its SHA-256 file.
2. Install using the client administrator's Windows account.
3. Open **Al Hassan Academy** from the desktop shortcut and create the first admin.
4. Configure the client's LiveKit project from the small Client Server window.

Data lives on the client computer in `%LOCALAPPDATA%\AlHassanAcademy`, outside the
program folder. Keep the Client Server window running/minimized. Later updates
back up before migrations and retain records/settings; uninstall retains data.

**Preview status:** Windows CI verified installation, sign-in, native process
startup, recurring-class timezone support, update backup, retained records, and
uninstall data preservation. The installer is unsigned. Check actual client
hardware, camera/microphone, video/screenshare, and backups before production
handover. Remote website access needs separate public HTTPS configuration.
WhatsApp requires the client's official business setup and recipient opt-in.

No client database, default admin password, or developer provider credentials
are included. An existing Mac database is not transferred automatically. Keep
its backup/live installation until client migration has been verified.

See [Windows installation and handover guide](https://github.com/Arshadqais/Al_hassan-quran-acedemy/blob/main/docs/windows-installer.md).
