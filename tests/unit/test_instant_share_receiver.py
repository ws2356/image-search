import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import SessionState
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.orchestrator import (
    INSTANT_SHARE_LIFECYCLE_EVENT,
    InstantShareReceiverOrchestrator,
)
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.tools.dts_event_bus import default_bus


def _connection_config():
    return ConnectionConfig.from_dict(
        {
            "session_id": str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": ["192.168.1.60"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
    )


class TestInstantShareReceiverOrchestrator(unittest.TestCase):
    def test_handle_connection_config_transitions_to_queued(self):
        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        connection_config = _connection_config()
        session = orchestrator.handle_connection_config(connection_config)
        self.assertEqual(session.state, SessionState.QUEUED)

    def test_handle_trust_handshake_received_transitions_to_negotiating(self):
        delivery_service = InstantShareDeliveryService()
        session_registry = InstantShareSessionRegistry()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
        )
        connection_config = _connection_config()
        session = orchestrator.handle_connection_config(connection_config)
        self.assertEqual(session.state, SessionState.QUEUED)
        received_events = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        orchestrator.handle_trust_handshake_received(
            session_id=session.connection_config.session_id,
            correlation_id=connection_config.correlation_id,
        )
        negotiating_events = [e for e in received_events if e["state"] == "negotiating"]
        self.assertEqual(len(negotiating_events), 1)

    def test_abort_session_transitions_to_aborted(self):
        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        connection_config = _connection_config()
        received_events = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        session = orchestrator.handle_connection_config(connection_config)
        orchestrator._session_registry.transition(
            session.connection_config.session_id, SessionState.TRANSFERRING
        )
        aborted = orchestrator.abort_session(session_id=session.connection_config.session_id)

        self.assertEqual(aborted.state.value, "aborted")
        self.assertEqual(received_events[-1]["state"], "aborted")
        self.assertEqual(received_events[-1]["error_code"], "USER_ABORTED")

    def test_fail_session_transitions_to_failed(self):
        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        connection_config = _connection_config()
        session = orchestrator.handle_connection_config(connection_config)
        orchestrator._session_registry.transition(
            session.connection_config.session_id, SessionState.NEGOTIATING
        )

        error = InstantShareError(
            error_code=__import__("dt_image_search.instant_sharing.contracts", fromlist=["ErrorCode"]).ErrorCode.TRANSFER_TIMEOUT,
            message="transfer timed out",
            correlation_id=connection_config.correlation_id,
        )
        failed = orchestrator.fail_session(
            session_id=session.connection_config.session_id, error=error
        )
        self.assertEqual(failed.state.value, "timed_out")

    def test_orchestrator_with_trust_session_registry(self):
        delivery_service = InstantShareDeliveryService()
        session_registry = InstantShareSessionRegistry()
        trust_registry = TrustSessionRegistry()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
            trust_session_registry=trust_registry,
        )
        self.assertIs(orchestrator.trust_session_registry, trust_registry)


if __name__ == "__main__":
    unittest.main()