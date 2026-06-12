import os
import sys
import unittest
import uuid
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    PayloadClass,
    SessionState,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.orchestrator import (
    InstantShareReceiverOrchestrator,
    _session_attributes,
)
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry


def _connection_config():
    return ConnectionConfig.from_dict(
        {
            "session_id": str(uuid.uuid4()),
            "mobile_port": 9876,
            "mobile_ip_list": ["192.168.1.100"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
    )


class SessionAttributesTests(unittest.TestCase):
    def test_session_attributes_contains_required_fields(self) -> None:
        config = _connection_config()
        attrs = _session_attributes(config)
        self.assertEqual(attrs["instant_share.session_id"], config.session_id)
        self.assertEqual(attrs["instant_share.correlation_id"], config.correlation_id)
        self.assertEqual(attrs["instant_share.payload_class"], "text")
        self.assertEqual(attrs["instant_share.target_intent"], "clipboard_only")
        self.assertEqual(attrs["instant_share.trust_mode"], "first_share")

    def test_session_attributes_overrides_correlation_id(self) -> None:
        config = _connection_config()
        attrs = _session_attributes(config, correlation_id="override-id")
        self.assertEqual(attrs["instant_share.correlation_id"], "override-id")


class TelemetrySpanTests(unittest.TestCase):
    @patch("dt_image_search.instant_sharing.orchestrator.log")
    def test_handle_connection_config_emits_log(self, mock_log) -> None:
        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        config = _connection_config()
        orchestrator.handle_connection_config(config)

        mock_log.assert_called_once()
        log_kwargs = mock_log.call_args
        self.assertEqual(log_kwargs[0][0], "info")
        self.assertIn("accepted", log_kwargs[1]["message"].lower())

    @patch("dt_image_search.instant_sharing.orchestrator.add_span")
    @patch("dt_image_search.instant_sharing.orchestrator.log")
    def test_handle_trust_handshake_received_emits_span_and_log(self, mock_log, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=None)
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        config = _connection_config()
        orchestrator.handle_connection_config(config)

        orchestrator.handle_trust_handshake_received(
            session_id=config.session_id,
            correlation_id=config.correlation_id,
        )

        span_calls = mock_span.call_args_list
        span_names = [call[0][0] for call in span_calls]
        self.assertIn("instant_share.trust.handshake.received", span_names)

    @patch("dt_image_search.instant_sharing.orchestrator.add_span")
    @patch("dt_image_search.instant_sharing.orchestrator.log")
    def test_handle_transfer_received_emits_span(self, mock_log, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=None)
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

        delivery_service = InstantShareDeliveryService()
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        config = _connection_config()
        orchestrator.handle_connection_config(config)
        orchestrator._session_registry.transition(config.session_id, SessionState.NEGOTIATING)

        orchestrator.handle_transfer_received(
            session_id=config.session_id,
            correlation_id=config.correlation_id,
        )

        span_calls = mock_span.call_args_list
        span_names = [call[0][0] for call in span_calls]
        self.assertIn("instant_share.transfer.received", span_names)


if __name__ == "__main__":
    unittest.main()