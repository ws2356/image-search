import faulthandler
import signal
import time
from pathlib import Path
from typing import Callable, Optional, TextIO


LogCallback = Callable[[str, str, str, str], None]


class CrashRecoveryManager:
    def __init__(
        self,
        app_data_path: Path,
        log_callback: LogCallback,
        marker_filename: str = "run.marker",
        native_dump_filename: str = "native_crash.dump.txt",
        max_native_dump_bytes: int = 128 * 1024,
    ) -> None:
        self._app_data_path = app_data_path
        self._log_callback = log_callback
        self._marker_path = self._app_data_path / marker_filename
        self._native_dump_path = self._app_data_path / native_dump_filename
        self._max_native_dump_bytes = max_native_dump_bytes
        self._dump_stream: Optional[TextIO] = None

    @property
    def marker_path(self) -> Path:
        return self._marker_path

    @property
    def native_dump_path(self) -> Path:
        return self._native_dump_path

    def mark_run_started(self, current_timestamp: Optional[int] = None) -> None:
        if self._marker_path.exists():
            try:
                stale_timestamp = self._marker_path.read_text(encoding="utf-8").strip()
            except Exception:
                stale_timestamp = "unknown"
            self._log(
                "warning",
                "previous_run_unclean",
                f"Detected stale run marker. Previous run may have crashed. marker_time={stale_timestamp}",
                "CrashRecoveryManager.mark_run_started",
            )

        timestamp = current_timestamp if current_timestamp is not None else int(time.time())
        self._marker_path.write_text(str(timestamp), encoding="utf-8")

    def clear_run_marker(self) -> None:
        try:
            if self._marker_path.exists():
                self._marker_path.unlink()
        except Exception as e:
            self._log(
                "warning",
                "run_marker_cleanup_failed",
                str(e),
                "CrashRecoveryManager.clear_run_marker",
            )

    def ingest_previous_native_crash_dump(self) -> None:
        if not self._native_dump_path.exists():
            return

        try:
            file_size = self._native_dump_path.stat().st_size
            if file_size <= 0:
                self._native_dump_path.unlink(missing_ok=True)
                return

            with self._native_dump_path.open("rb") as f:
                dump_bytes = f.read(self._max_native_dump_bytes)

            dump_text = dump_bytes.decode("utf-8", errors="replace")
            was_truncated = file_size > len(dump_bytes)
            truncated_note = " (truncated)" if was_truncated else ""
            self._log(
                "error",
                "native_crash_dump",
                f"Recovered native crash dump from previous run. size_bytes={file_size}{truncated_note}\n{dump_text}",
                "CrashRecoveryManager.ingest_previous_native_crash_dump",
            )
            self._native_dump_path.unlink(missing_ok=True)
        except OSError as e:
            self._log(
                "warning",
                "native_crash_dump_read_failed",
                str(e),
                "CrashRecoveryManager.ingest_previous_native_crash_dump",
            )

    def enable_native_crash_dump_capture(self) -> None:
        try:
            self._dump_stream = self._native_dump_path.open("w", encoding="utf-8")
            faulthandler.enable(file=self._dump_stream, all_threads=True)
            register_handler = getattr(faulthandler, "register", None)
            if callable(register_handler):
                for sig in self._native_crash_signals():
                    try:
                        register_handler(sig, file=self._dump_stream, all_threads=True, chain=True)
                    except (ValueError, OSError, RuntimeError):
                        continue
        except OSError as e:
            self._log(
                "warning",
                "native_crash_dump_open_failed",
                str(e),
                "CrashRecoveryManager.enable_native_crash_dump_capture",
            )
        except Exception as e:
            self._log(
                "warning",
                "native_crash_dump_enable_failed",
                str(e),
                "CrashRecoveryManager.enable_native_crash_dump_capture",
            )

    def disable_native_crash_dump_capture(self) -> None:
        unregister_handler = getattr(faulthandler, "unregister", None)
        if callable(unregister_handler):
            for sig in self._native_crash_signals():
                try:
                    unregister_handler(sig)
                except RuntimeError:
                    continue

        try:
            faulthandler.disable()
        except RuntimeError:
            pass

        if self._dump_stream is not None:
            try:
                self._dump_stream.flush()
                self._dump_stream.close()
            except OSError as e:
                self._log(
                    "warning",
                    "native_crash_dump_close_failed",
                    str(e),
                    "CrashRecoveryManager.disable_native_crash_dump_capture",
                )
            finally:
                self._dump_stream = None

        try:
            if self._native_dump_path.exists() and self._native_dump_path.stat().st_size == 0:
                self._native_dump_path.unlink()
        except OSError as e:
            self._log(
                "warning",
                "native_crash_dump_cleanup_failed",
                str(e),
                "CrashRecoveryManager.disable_native_crash_dump_capture",
            )

    def _log(self, severity: str, error_type: str, message: str, where: str) -> None:
        self._log_callback(severity, error_type, message, where)

    @staticmethod
    def _native_crash_signals() -> list:
        signal_names = ["SIGABRT", "SIGBUS", "SIGFPE", "SIGILL", "SIGSEGV"]
        available_signals = []
        for name in signal_names:
            if hasattr(signal, name):
                available_signals.append(getattr(signal, name))
        return available_signals
