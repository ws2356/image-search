"""Unit tests for InstantShareSessionRegistry."""

import unittest

from dt_image_search.instant_sharing.contracts import (
    InstantShareMetadata,
    PayloadClass,
    SessionState,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


class TestBootstrapRevisit(unittest.TestCase):
    def setUp(self):
        self.registry = InstantShareSessionRegistry()

    def _make_config(self, session_id="test-session-id", payload_class=PayloadClass.TEXT):
        return ConnectionConfig(
            session_id=session_id,
            mobile_port=1,
            mobile_ip_list=("127.0.0.1",),
            correlation_id="test-correlation-id",
            metadata=InstantShareMetadata(
                payload_class=payload_class,
                target_intent=TargetIntent.CLIPBOARD_ONLY,
                trust_mode=TrustMode.TRUSTED_DIRECT,
            ),
        )

    def test_bootstrap_revisit_creates_session_at_transferring_state(self):
        config = self._make_config()
        session = self.registry.bootstrap_revisit(config)

        self.assertEqual(session.state, SessionState.TRANSFERRING)
        self.assertEqual(
            session.connection_config.metadata.trust_mode,
            TrustMode.TRUSTED_DIRECT,
        )
        self.assertEqual(session.connection_config.session_id, "test-session-id")

    def test_bootstrap_revisit_overrides_active_session(self):
        config1 = self._make_config(session_id="session-1")
        config2 = self._make_config(session_id="session-2")

        self.registry.bootstrap_revisit(config1)
        session2 = self.registry.bootstrap_revisit(config2)

        self.assertEqual(session2.connection_config.session_id, "session-2")
        active = self.registry.get_active_session()
        self.assertIsNotNone(active)
        self.assertEqual(active.connection_config.session_id, "session-2")

    def test_bootstrap_revisit_sets_trusted_direct_mode(self):
        config = self._make_config()
        session = self.registry.bootstrap_revisit(config)

        self.assertEqual(
            session.connection_config.metadata.trust_mode,
            TrustMode.TRUSTED_DIRECT,
        )


if __name__ == "__main__":
    unittest.main()
