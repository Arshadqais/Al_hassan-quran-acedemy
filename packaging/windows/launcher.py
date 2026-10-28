"""Windowed client launcher; no Python/Docker installation is needed on the client."""
import ctypes
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sys
import tkinter as tk
from tkinter import messagebox, ttk
from dotenv import dotenv_values
from desktop_runtime import DesktopRuntime, DesktopError, API_PORT

MUTEX = r"Local\AlHassanAcademyServer"


class Form(tk.Toplevel):
    def __init__(self, parent, title, fields, submit):
        super().__init__(parent)
        self.title(title)
        self.transient(parent)
        self.grab_set()
        self.resizable(False, False)
        self.entries = {}
        self.submit = submit
        if len(fields) > 6:
            self.geometry("560x660")
            canvas = tk.Canvas(self, highlightthickness=0)
            scrollbar = ttk.Scrollbar(self, orient="vertical", command=canvas.yview)
            canvas.configure(yscrollcommand=scrollbar.set)
            scrollbar.pack(side="right", fill="y")
            canvas.pack(side="left", fill="both", expand=True)
            frame = ttk.Frame(canvas, padding=22)
            item = canvas.create_window((0, 0), window=frame, anchor="nw")
            frame.bind("<Configure>", lambda _: canvas.configure(scrollregion=canvas.bbox("all")))
            canvas.bind("<Configure>", lambda e: canvas.itemconfigure(item, width=e.width))
        else:
            frame = ttk.Frame(self, padding=22)
            frame.pack(fill="both", expand=True)
        for key, label, secret, value in fields:
            ttk.Label(frame, text=label).pack(anchor="w", pady=(7, 2))
            entry = ttk.Entry(frame, width=48, show="•" if secret else "")
            entry.insert(0, value or "")
            entry.pack(fill="x")
            self.entries[key] = entry
        self.error = ttk.Label(frame, text="", foreground="#aa2222", wraplength=380)
        self.error.pack(pady=8)
        self.button = ttk.Button(frame, text="Save", command=self.save)
        self.button.pack(anchor="e")
        self.protocol("WM_DELETE_WINDOW", self.destroy)

    def save(self):
        values = {key: entry.get() for key, entry in self.entries.items()}
        if "confirm" in values and values.pop("confirm") != values.get("password"):
            self.error.config(text="Passwords do not match.")
            return
        self.button.config(state="disabled")
        self.submit(values, self)


class Academy:
    def __init__(self, root, runtime):
        self.root, self.runtime = root, runtime
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.busy, self.ready = False, False
        root.title("Al Hassan Academy — Client Server")
        root.geometry("560x520")
        root.protocol("WM_DELETE_WINDOW", self.close)
        frame = ttk.Frame(root, padding=26)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="Al Hassan Online Quran Academy", font=("Segoe UI", 17, "bold")).pack(anchor="w")
        ttk.Label(frame, text="Your academy data is stored on this computer.").pack(anchor="w", pady=(8, 18))
        self.status = ttk.Label(frame, text="Preparing your academy…", wraplength=490)
        self.status.pack(anchor="w", pady=10)
        self.open_button = ttk.Button(frame, text="Open academy", command=runtime.open_app, state="disabled")
        self.open_button.pack(fill="x", pady=4)
        self.buttons = []
        for label, command in [("Configure video calls", self.video), ("Configure WhatsApp reminders", self.whatsapp),
            ("Download / refresh Quran library", self.quran), ("Back up database", self.backup)]:
            button = ttk.Button(frame, text=label, command=command, state="disabled")
            button.pack(fill="x", pady=3)
            self.buttons.append(button)
        ttk.Button(frame, text="Open client data folder", command=lambda: os.startfile(runtime.data_dir)).pack(fill="x", pady=3)
        ttk.Button(frame, text="Stop academy and exit", command=self.close).pack(fill="x", pady=8)
        self.work(runtime.prepare, self.prepared, "Starting the client database and checking updates…")

    def work(self, operation, done, label, failed=None):
        if self.busy:
            return
        self.busy = True
        self.status.config(text=label)
        self.open_button.config(state="disabled")
        for button in self.buttons:
            button.config(state="disabled")
        future = self.executor.submit(operation)
        def poll():
            if not future.done():
                self.root.after(100, poll)
                return
            self.busy = False
            if self.ready:
                self.open_button.config(state="normal")
                for button in self.buttons:
                    button.config(state="normal")
            try:
                result = future.result()
            except Exception as error:
                text = str(error) if isinstance(error, DesktopError) else "Setup could not complete. Your existing data was kept. Contact your developer."
                self.status.config(text=text)
                if failed:
                    failed(text)
                else:
                    messagebox.showerror("Academy setup", text, parent=self.root)
                return
            done(result)
        self.root.after(100, poll)

    def prepared(self, has_admin):
        if has_admin:
            self.start()
        else:
            self.status.config(text="Create your first administrator account to finish setup.")
            Form(self.root, "Create academy administrator", [
                ("name", "Administrator name", False, ""), ("email", "Email", False, ""),
                ("password", "Password (12–128 characters)", True, ""), ("confirm", "Confirm password", True, "")], self.create_admin)

    def create_admin(self, values, form):
        self.work(lambda: self.runtime.helper("create-admin", values),
            lambda _: (form.destroy(), self.start()), "Creating your administrator…",
            failed=lambda text: (form.error.config(text=text), form.button.config(state="normal")))

    def start(self):
        def operation():
            self.runtime.start_api()
            self.runtime.open_app()
        self.work(operation, self.started, "Starting the academy app…")

    def started(self, _):
        self.ready = True
        self.open_button.config(state="normal")
        for button in self.buttons:
            button.config(state="normal")
        self.status.config(text="Academy is running. Keep this server window open or minimized for classes and reminders. Closing the Flutter window does not stop the server.")
        self.root.after(1000, self.root.iconify)

    def configure(self, title, fields, action):
        values = dict(dotenv_values(self.runtime.env_file))
        form = Form(self.root, title, [(key, label, secret, values.get(key, default)) for key, label, secret, default in fields],
            lambda payload, dialog: self.save_config(payload, dialog, action))
        return form

    def save_config(self, payload, form, action):
        if action == "configure-video":
            payload = {"url": payload["LIVEKIT_URL"], "key": payload["LIVEKIT_API_KEY"], "secret": payload["LIVEKIT_API_SECRET"]}
        def operation():
            self.runtime.helper(action, payload, timeout=90)
            self.runtime.restart_api()
        self.work(operation, lambda _: (form.destroy(), self.status.config(text="Configuration verified and saved privately. Academy backend restarted.")),
            "Verifying configuration; no message will be sent…", failed=lambda text: (form.error.config(text=text), form.button.config(state="normal")))

    def video(self):
        self.configure("Configure LiveKit video", [("LIVEKIT_URL", "LiveKit WSS project URL", False, ""),
            ("LIVEKIT_API_KEY", "API key", True, ""), ("LIVEKIT_API_SECRET", "API secret", True, "")], "configure-video")

    def whatsapp(self):
        self.configure("Configure WhatsApp Business", [
            ("WHATSAPP_PHONE_NUMBER_ID", "Sender phone-number ID", False, ""),
            ("WHATSAPP_WABA_ID", "WhatsApp business account ID", False, ""),
            ("WHATSAPP_ACCESS_TOKEN", "Access token", True, ""),
            ("WHATSAPP_TEMPLATE_NAME", "Approved template name", False, "class_reminder"),
            ("WHATSAPP_TEMPLATE_LANGUAGE", "Template language", False, "en"),
            ("WHATSAPP_API_VERSION", "Graph API version", False, "v23.0"),
            ("REMINDER_MINUTES", "Minutes before class (1–120)", False, "10"),
            ("REMINDER_TIMEZONE", "Timezone", False, "Asia/Karachi"),
            ("WHATSAPP_APP_SECRET", "App secret (optional delivery receipts)", True, ""),
            ("WHATSAPP_VERIFY_TOKEN", "Webhook verification token (optional)", True, "")], "configure-whatsapp")

    def quran(self):
        self.work(lambda: self.runtime.helper("download-quran", timeout=300),
            lambda _: self.status.config(text="All Quran editions are cached on this computer."), "Downloading Quran editions…")

    def backup(self):
        self.work(self.runtime.backup, lambda p: (self.status.config(text="Database backup completed."),
            messagebox.showinfo("Backup saved", f"Saved privately on this computer:\n{p}", parent=self.root)), "Backing up the database…")

    def close(self):
        if self.busy:
            messagebox.showinfo("Please wait", "An academy operation is still running. Wait for it to finish before exiting.", parent=self.root)
            return
        if self.ready and not messagebox.askyesno("Stop academy?", "This stops the backend and reminders. Your database files remain on this computer.", parent=self.root):
            return
        def finished(_):
            self.executor.shutdown(wait=False)
            self.root.destroy()
        self.work(self.runtime.stop, finished, "Stopping the academy and saving database state…")


def main():
    if os.name != "nt":
        raise SystemExit("The packaged desktop launcher is for Windows.")
    # The same mutex is checked by the installer before replacing application files.
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateMutexW.restype = ctypes.c_void_p
    kernel.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_wchar_p]
    handle = kernel.CreateMutexW(None, True, MUTEX)
    if not handle:
        raise OSError("Could not create academy application lock")
    already_running = ctypes.get_last_error() == 183
    root = tk.Tk()
    if already_running:
        root.withdraw()
        messagebox.showinfo("Academy already running", "Use the existing Al Hassan Academy server window in your taskbar, then click Open academy.")
        root.destroy()
        return
    app_dir = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent / "bundle"
    data_dir = Path(os.environ["LOCALAPPDATA"]) / "AlHassanAcademy"
    try:
        Academy(root, DesktopRuntime(app_dir, data_dir))
        root.mainloop()
    finally:
        kernel.ReleaseMutex(ctypes.c_void_p(handle))
        kernel.CloseHandle(ctypes.c_void_p(handle))


if __name__ == "__main__":
    main()
