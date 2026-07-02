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
    def test_bootstrap_allows_concurrent_sessions(self):
        """Multi-session: second bootstrap creates independent session."""
        registry = InstantShareSessionRegistry()
        session1 = registry.bootstrap(_config())
        session2 = registry.bootstrap(_config())

        self.assertEqual(session1.state, SessionState.BOOTSTRAPPED)
        self.assertEqual(session2.state, SessionState.BOOTSTRAPPED)
        self.assertNotEqual(
            session1.connection_config.session_id,
            session2.connection_config.session_id,
        )

    def test_bootstrap_is_idempotent_for_same_session_id(self):
        """Multi-session: same session_id re-bootstrap returns existing session."""
        registry = InstantShareSessionRegistry()
        config = _config()
        session1 = registry.bootstrap(config)
        session2 = registry.bootstrap(config)

        self.assertIs(session1, session2)

    def test_bootstrap_enforces_capacity_limit(self):
        """Multi-session: MAX_SESSIONS reached raises RECEIVER_BUSY_MAX_SESSIONS."""
        registry = InstantShareSessionRegistry(max_sessions=2)
        # Bootstrap 2 sessions (non-terminal → counts against capacity)
        s1 = registry.bootstrap(_config())
        s2 = registry.bootstrap(_config())
        registry.transition(s1.connection_config.session_id, SessionState.QUEUED)
        registry.transition(s2.connection_config.session_id, SessionState.QUEUED)

        with self.assertRaises(InstantShareError) as exc_info:
            registry.bootstrap(_config())

        self.assertEqual(exc_info.exception.error_code.value, "RECEIVER_BUSY_MAX_SESSIONS")
        self.assertTrue(exc_info.exception.retryable)

    def test_capacity_frees_after_session_completes(self):
        """Multi-session: terminal session not counted toward limit."""
        registry = InstantShareSessionRegistry(max_sessions=2)
        s1 = registry.bootstrap(_config())
        s2 = registry.bootstrap(_config())
        registry.transition(s1.connection_config.session_id, SessionState.QUEUED)
        registry.transition(s2.connection_config.session_id, SessionState.QUEUED)

        # Complete session 2: QUEUED → FAILED (valid transition)
        registry.transition(s2.connection_config.session_id, SessionState.FAILED)

        # Should now allow a new session
        s3 = registry.bootstrap(_config())
        self.assertEqual(s3.state, SessionState.BOOTSTRAPPED)

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

    def test_get_active_sessions_filters_terminal(self):
        """get_active_sessions returns only non-terminal sessions."""
        registry = InstantShareSessionRegistry()
        s1 = registry.bootstrap(_config())
        s2 = registry.bootstrap(_config())
        registry.transition(s1.connection_config.session_id, SessionState.QUEUED)
        registry.transition(s2.connection_config.session_id, SessionState.QUEUED)
        # QUEUED → FAILED is a valid terminal transition
        registry.transition(s2.connection_config.session_id, SessionState.FAILED)

        active = registry.get_active_sessions()
        self.assertEqual(len(active), 1)
        self.assertEqual(active[0].connection_config.session_id,
                         s1.connection_config.session_id)

    def test_get_session_returns_none_for_missing(self):
        registry = InstantShareSessionRegistry()
        self.assertIsNone(registry.get_session("nonexistent"))

    def test_set_batch_metadata(self):
        """Setting batch metadata updates image_count and keeps session frozen."""
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())
        updated = registry.set_batch_metadata(session.connection_config.session_id, image_count=5)

        self.assertEqual(updated.image_count, 5)
        self.assertEqual(updated.received_count, 0)
        # Verify the stored session is updated
        stored = registry.get_session(session.connection_config.session_id)
        self.assertEqual(stored.image_count, 5)

    def test_increment_received_count(self):
        """Increment received_count atomically within a batch."""
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())
        registry.set_batch_metadata(session.connection_config.session_id, image_count=3)

        for i in range(1, 4):
            updated = registry.increment_received_count(session.connection_config.session_id)
            self.assertEqual(updated.received_count, i)

        stored = registry.get_session(session.connection_config.session_id)
        self.assertEqual(stored.received_count, 3)
        self.assertEqual(stored.image_count, 3)

    def test_session_defaults_to_zero_counts(self):
        """New sessions start with image_count=0 and received_count=0."""
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())
        self.assertEqual(session.image_count, 0)
        self.assertEqual(session.received_count, 0)

    def test_increment_received_count_without_batch_metadata(self):
        """Increment works even without setting image_count first (default 0)."""
        registry = InstantShareSessionRegistry()
        session = registry.bootstrap(_config())
        updated = registry.increment_received_count(session.connection_config.session_id)
        self.assertEqual(updated.received_count, 1)
        self.assertEqual(updated.image_count, 0)


if __name__ == "__main__":
    unittest.main()
