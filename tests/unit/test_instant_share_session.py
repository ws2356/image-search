import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import SessionState
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


def _config(session_id: str | None = None):
    return ConnectionConfig.from_dict(
        {
            "session_id": session_id or str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": ["192.168.1.50"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
    )


class TestInstantShareSessionRegistry(unittest.TestCase):
    def test_bootstrap_rejects_second_active_session(self):
        registry = InstantShareSessionRegistry()
        registry.bootstrap(_config())

        with self.assertRaises(InstantShareError) as exc_info:
            registry.bootstrap(_config())

        self.assertEqual(exc_info.exception.error_code.value, "RECEIVER_BUSY_SINGLE_SESSION")

    def test_terminal_session_allows_new_bootstrap(self):
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())
        registry.transition(session.connection_config.session_id, SessionState.QUEUED)
        registry.transition(session.connection_config.session_id, SessionState.FAILED)

        new_session = registry.bootstrap(_config())

        self.assertEqual(new_session.state, SessionState.BOOTSTRAPPED)

    def test_invalid_transition_raises(self):
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())

        with self.assertRaises(InstantShareError):
            registry.transition(session.connection_config.session_id, SessionState.DONE)


if __name__ == "__main__":
    unittest.main()