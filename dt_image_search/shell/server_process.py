# Supervises the index server child process: spawns it with a one-time token,
# parses the DTS_READY stdout handshake, and restarts it once on unexpected
# exit (deliberately not unlimited — repeated crashes surface as an exit).
import os
import secrets
import subprocess
import sys
import threading

from pc_common.telemetry.telemetry_client import log


class ServerProcess:
    def __init__(self, on_ready=None, on_exit=None, python_exe: str | None = None, extra_args=None):
        self._on_ready = on_ready or (lambda port: None)
        self._on_exit = on_exit or (lambda: None)
        self._python_exe = python_exe or sys.executable
        self._extra_args = list(extra_args or [])
        self.token = secrets.token_urlsafe(24)
        self.port: int | None = None
        self._proc: subprocess.Popen | None = None
        self._reader_thread: threading.Thread | None = None
        self._restarts = 0
        self._stopped = False
        self._process_lock = threading.Lock()

    def start(self) -> None:
        self._spawn()

    def stop(self) -> None:
        with self._process_lock:
            self._stopped = True
            proc = self._proc
            reader = self._reader_thread
        if proc is not None:
            try:
                proc.terminate()
            except OSError:
                pass
        if reader is not None and reader is not threading.current_thread():
            reader.join(timeout=10)
            if reader.is_alive() and proc is not None:
                try:
                    proc.kill()
                except OSError:
                    pass
                reader.join(timeout=5)

    def child_command(self) -> list:
        """The command line for the index server child process.

        Dev runs use `python -m`; a PyInstaller bundle has no embedded
        python, so the sibling executable bundled by COLLECT is launched with
        an explicit static dir pointing at the bundled web UI resources.
        """
        if getattr(sys, "frozen", False):
            sibling = os.path.join(os.path.dirname(sys.executable), "AuSearchIndexServer")
            if sys.platform == "win32":
                sibling += ".exe"
            static_dir = os.path.join(sys._MEIPASS, "webui", "dist")
            return [sibling, "--auth-token", self.token, "--static-dir", static_dir]
        return [self._python_exe, "-m", "dt_image_search.index_server", "--auth-token", self.token, *self._extra_args]

    def _spawn(self) -> None:
        with self._process_lock:
            if self._stopped:
                return
            self._proc = subprocess.Popen(
                self.child_command(),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
            )
            self._reader_thread = threading.Thread(target=self._read_loop, args=(self._proc,), daemon=True)
            self._reader_thread.start()

    def _read_loop(self, proc: subprocess.Popen) -> None:
        for line in proc.stdout:
            line = line.strip()
            if line.startswith("DTS_READY "):
                try:
                    port = int(line.removeprefix("DTS_READY "))
                    if not 0 < port < 65536:
                        raise ValueError("port out of range")
                except ValueError:
                    log("warning", message="ServerProcess: ignoring invalid READY announcement")
                    continue
                self.port = port
                self._on_ready(self.port)
        proc.stdout.close()
        proc.wait()

        if self._stopped:
            return
        self._restarts += 1
        if self._restarts <= 1:
            log("warning", message="ServerProcess: index server exited unexpectedly; restarting once")
            try:
                self._spawn()
            except OSError as error:
                log("error", message=f"ServerProcess: restart failed: {error}")
                self._on_exit()
        else:
            log("error", message="ServerProcess: index server exited again; giving up")
            self._on_exit()
