import os
import sys
import threading
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.contracts import SessionState
from dt_image_search.instant_sharing.runtime import InstantShareRuntime


class _ClipboardRecorder:
    def __init__(self):
        self.texts = []
        self.images = []

    def write_text(self, text: str) -> None:
        self.texts.append(text)

    def write_image_bytes(self, image_bytes: bytes) -> None:
        self.images.append(image_bytes)


def _connection_config_payload():
    return {
        "session_id": str(uuid.uuid4()),
        "mobile_port": 8443,
        "mobile_ip_list": ["192.168.1.20", "fe80::10"],
        "correlation_id": str(uuid.uuid4()),
        "flow_id": "instant_share",
        "payload_class": "text",
        "target_intent": "clipboard_only",
        "trust_mode": "first_share",
    }


class TestInstantShareRuntime(unittest.TestCase):
    def test_runtime_start_respects_feature_flag(self):
        disabled_runtime = InstantShareRuntime(
            is_enabled=lambda: False,
            clipboard_writer=_ClipboardRecorder(),
        )

        self.assertFalse(disabled_runtime.start())
        self.assertFalse(disabled_runtime.is_running)

    def test_runtime_start_and_stop_manage_ble_daemon(self):
        heartbeat_event = threading.Event()
        runtime = InstantShareRuntime(
            is_enabled=lambda: True,
            clipboard_writer=_ClipboardRecorder(),
            heartbeat=heartbeat_event.set,
            poll_interval_seconds=0.01,
        )

        self.assertTrue(runtime.start())
        self.assertTrue(heartbeat_event.wait(timeout=1.0))
        self.assertTrue(runtime.is_running)

        runtime.stop()

        self.assertFalse(runtime.is_running)

    def test_runtime_bootstraps_connection_config_into_queued_session(self):
        runtime = InstantShareRuntime(
            is_enabled=lambda: False,
            clipboard_writer=_ClipboardRecorder(),
        )

        session = runtime.bootstrap_connection_config(_connection_config_payload())

        self.assertEqual(session.state, SessionState.QUEUED)
        self.assertEqual(runtime.ble_service.active_connection_config.session_id, session.connection_config.session_id)
        self.assertEqual(runtime.session_registry.get_active_session().state, SessionState.QUEUED)


if __name__ == "__main__":
    unittest.main()