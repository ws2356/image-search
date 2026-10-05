# Supervises the index server child process: spawns it with a one-time token,
# parses the DTS_READY stdout handshake, and restarts it once on unexpected
# exit (deliberately not unlimited — repeated crashes surface as an exit).
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

    def start(self) -> None:
        self._spawn()

    def stop(self) -> None:
        self._stopped = True
        proc = self._proc
        if proc is not None:
            try:
                proc.terminate()
            except OSError:
                pass
        reader = self._reader_thread
        if reader is not None:
            reader.join(timeout=10)

    def _spawn(self) -> None:
        args = [
            self._python_exe,
            "-m",
            "dt_image_search.index_server",
            "--auth-token",
            self.token,
            *self._extra_args,
        ]
        self._proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()

    def _read_loop(self) -> None:
        for line in self._proc.stdout:
            line = line.strip()
            if line.startswith("DTS_READY "):
                self.port = int(line.split()[1])
                self._on_ready(self.port)
        self._proc.wait()

        if self._stopped:
            self._on_exit()
            return
        self._restarts += 1
        if self._restarts <= 1:
            log("warning", message="ServerProcess: index server exited unexpectedly; restarting once")
            self._spawn()
        else:
            log("error", message="ServerProcess: index server exited again; giving up")
            self._on_exit()
