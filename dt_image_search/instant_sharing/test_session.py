"""Unit tests for InstantShareSessionRegistry bootstrap_revisit."""

import unittest
import uuid

from dt_image_search.instant_sharing.contracts import (
    InstantShareMetadata,
    PayloadClass,
    SessionState,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.mdns import BootstrapRequest, ConnectionConfig
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


class TestBootstrapRevisit(unittest.TestCase):
    def setUp(self):
        self.registry = InstantShareSessionRegistry()

    def _make_config(self, session_id=None, payload_class=PayloadClass.TEXT):
        return ConnectionConfig(
            session_id=session_id or str(uuid.uuid4()),
            mobile_port=1,
            mobile_ip_list=("127.0.0.1",),
            correlation_id=str(uuid.uuid4()),
            metadata=InstantShareMetadata(
                payload_class=payload_class,
                target_intent=TargetIntent.CLIPBOARD_ONLY,
                trust_mode=TrustMode.TRUSTED_DIRECT,
            ),
        )

    def test_bootstrap_revisit_creates_session_at_transferring_state(self):
        sid = str(uuid.uuid4())
        config = self._make_config(session_id=sid)
        session = self.registry.bootstrap_revisit(config)

        self.assertEqual(session.state, SessionState.TRANSFERRING)
        self.assertEqual(
            session.connection_config.metadata.trust_mode,
            TrustMode.TRUSTED_DIRECT,
        )
        self.assertEqual(session.connection_config.session_id, sid)

    def test_bootstrap_revisit_coexists_with_other_sessions(self):
        """Multi-session: revisit creates independent session alongside existing ones."""
        sid1 = str(uuid.uuid4())
        sid2 = str(uuid.uuid4())
        config1 = self._make_config(session_id=sid1)
        config2 = self._make_config(session_id=sid2)

        session1 = self.registry.bootstrap_revisit(config1)
        session2 = self.registry.bootstrap_revisit(config2)

        self.assertEqual(session2.connection_config.session_id, sid2)
        # Both sessions should exist independently
        self.assertIsNotNone(self.registry.get_session(sid1))
        self.assertIsNotNone(self.registry.get_session(sid2))
        self.assertEqual(self.registry.get_session(sid1).state,
                         SessionState.TRANSFERRING)

    def test_bootstrap_revisit_sets_trusted_direct_mode(self):
        config = self._make_config()
        session = self.registry.bootstrap_revisit(config)

        self.assertEqual(
            session.connection_config.metadata.trust_mode,
            TrustMode.TRUSTED_DIRECT,
        )


class TestConnectionConfigShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        config = ConnectionConfig(
            session_id="a",
            mobile_port=8080,
            mobile_ip_list=("192.168.1.1",),
            correlation_id="abc123",
            metadata=InstantShareMetadata(
                payload_class=PayloadClass.TEXT,
                target_intent=TargetIntent.CLIPBOARD_ONLY,
                trust_mode=TrustMode.TRUSTED_DIRECT,
            ),
        )
        # Should not raise
        config.validate()

    def test_validate_rejects_empty_session_id(self):
        with self.assertRaises(ValueError):
            ConnectionConfig(
                session_id="",
                mobile_port=8080,
                mobile_ip_list=("192.168.1.1",),
                correlation_id="abc123",
                metadata=InstantShareMetadata(
                    payload_class=PayloadClass.TEXT,
                    target_intent=TargetIntent.CLIPBOARD_ONLY,
                    trust_mode=TrustMode.TRUSTED_DIRECT,
                ),
            ).validate()


class TestBootstrapRequestShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        req = BootstrapRequest(
            session_id="ff",
            mobile_port=8080,
            mobile_ip_list=("192.168.1.1",),
            correlation_id="abc123",
            payload_class="text",
            target_intent="clipboard_only",
        )
        # Should not raise
        req.validate()

    def test_validate_rejects_empty_session_id(self):
        with self.assertRaises(ValueError):
            BootstrapRequest(
                session_id="",
                mobile_port=8080,
                mobile_ip_list=("192.168.1.1",),
                correlation_id="abc123",
                payload_class="text",
                target_intent="clipboard_only",
            ).validate()


if __name__ == "__main__":
    unittest.main()
