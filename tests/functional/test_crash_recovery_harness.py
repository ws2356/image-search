import os
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from dt_image_search.telemetry.crash_support import CrashRecoveryManager


class TestCrashRecoveryHarness(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp_dir = tempfile.mkdtemp(prefix="crash-recovery-harness-")
        self._app_data_path = Path(self._tmp_dir)
        self._events = []

    def tearDown(self) -> None:
        shutil.rmtree(self._tmp_dir, ignore_errors=True)

    def _log_callback(self, severity: str, error_type: str = "", message: str = "", where: str = "") -> None:
        self._events.append(
            {
                "severity": severity,
                "error_type": error_type,
                "message": message,
                "where": where,
            }
        )

    @unittest.skipUnless(hasattr(signal, "SIGABRT"), "SIGABRT is required for deterministic crash harness")
    def test_marker_and_native_dump_recovery_flow(self) -> None:
        child_code = textwrap.dedent(
            """
            import os
            import signal
            from pathlib import Path

            from dt_image_search.telemetry.crash_support import CrashRecoveryManager


            app_data_path = Path(os.environ["CRASH_TEST_APP_DATA"])
            manager = CrashRecoveryManager(app_data_path, lambda *args, **kwargs: None)
            manager.enable_native_crash_dump_capture()
            manager.mark_run_started(current_timestamp=1700000000)
            if hasattr(signal, "raise_signal"):
                signal.raise_signal(signal.SIGABRT)
            os.abort()
            """
        )

        env = os.environ.copy()
        env["CRASH_TEST_APP_DATA"] = str(self._app_data_path)

        proc = subprocess.run(
            [
                sys.executable,
                "-c",
                child_code,
            ],
            env=env,
            cwd=Path(__file__).resolve().parents[2],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(proc.returncode, 0, "child process should crash")

        manager = CrashRecoveryManager(self._app_data_path, self._log_callback)

        self.assertTrue(manager.marker_path.exists(), "run marker should remain after crash")
        self.assertTrue(manager.native_dump_path.exists(), "native crash dump should exist after crash")
        self.assertGreater(manager.native_dump_path.stat().st_size, 0, "native crash dump should not be empty")

        manager.ingest_previous_native_crash_dump()
        self.assertFalse(manager.native_dump_path.exists(), "native crash dump should be removed after ingestion")

        manager.mark_run_started(current_timestamp=1700000001)
        self.assertTrue(manager.marker_path.exists(), "run marker should be re-created for current run")

        unclean_events = [e for e in self._events if e["error_type"] == "previous_run_unclean"]
        self.assertGreaterEqual(len(unclean_events), 1, "stale marker warning should be emitted")

        native_dump_events = [e for e in self._events if e["error_type"] == "native_crash_dump"]
        self.assertGreaterEqual(len(native_dump_events), 1, "native crash dump should be ingested into logs")

        manager.clear_run_marker()
        self.assertFalse(manager.marker_path.exists(), "run marker should be cleared on clean shutdown")


if __name__ == "__main__":
    unittest.main()
