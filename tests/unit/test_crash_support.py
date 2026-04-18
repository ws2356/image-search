import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.telemetry.crash_support import CrashRecoveryManager


class TestCrashRecoveryManager(unittest.TestCase):
    def setUp(self) -> None:
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)
        self._events: list[dict[str, str]] = []
        self._manager = CrashRecoveryManager(
            app_data_path=Path(self._temp_dir.name),
            log_callback=self._log_callback,
        )

    def _log_callback(self, severity: str, error_type: str = "", message: str = "", where: str = "") -> None:
        self._events.append(
            {
                "severity": severity,
                "error_type": error_type,
                "message": message,
                "where": where,
            }
        )

    def test_enable_disable_succeeds_when_register_apis_are_unavailable(self):
        fake_faulthandler = SimpleNamespace(
            enable=Mock(),
            disable=Mock(),
        )

        with patch("dt_image_search.telemetry.crash_support.faulthandler", fake_faulthandler):
            self._manager.enable_native_crash_dump_capture()
            self._manager.disable_native_crash_dump_capture()

        fake_faulthandler.enable.assert_called_once()
        fake_faulthandler.disable.assert_called_once()
        self.assertFalse(
            any(event["error_type"] == "native_crash_dump_enable_failed" for event in self._events)
        )
        self.assertIsNone(self._manager._dump_stream)

    def test_enable_disable_uses_register_and_unregister_when_available(self):
        fake_faulthandler = SimpleNamespace(
            enable=Mock(),
            disable=Mock(),
            register=Mock(),
            unregister=Mock(),
        )

        with patch("dt_image_search.telemetry.crash_support.faulthandler", fake_faulthandler), patch.object(
            CrashRecoveryManager,
            "_native_crash_signals",
            return_value=[1, 2],
        ):
            self._manager.enable_native_crash_dump_capture()
            self._manager.disable_native_crash_dump_capture()

        self.assertEqual(fake_faulthandler.register.call_count, 2)
        self.assertEqual(fake_faulthandler.unregister.call_count, 2)


if __name__ == "__main__":
    unittest.main()
