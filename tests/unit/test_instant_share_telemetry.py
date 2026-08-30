import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.mdns import ConnectionConfig
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
from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.instant_sharing.unix_socket_server import UnixSocketHttpServer
from dt_image_search.scripts.instant_share_agent_main import _AgentHeartbeat


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


class UnixSocketServerTelemetryTests(unittest.TestCase):
    def _mock_span(self, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=MagicMock())
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

    @patch("dt_image_search.instant_sharing.unix_socket_server.add_span")
    @patch("dt_image_search.instant_sharing.unix_socket_server.log")
    def test_start_and_stop_emit_span_and_logs(self, mock_log, mock_span) -> None:
        self._mock_span(mock_span)
        with tempfile.TemporaryDirectory() as tmp:
            server = UnixSocketHttpServer(
                request_handler=lambda body: {},
                socket_path=Path(tmp) / "is.sock",
            )
            self.assertTrue(server.start())
            server.stop()

        span_names = [call[0][0] for call in mock_span.call_args_list]
        self.assertIn("unix_socket_server.start", span_names)

        log_wheres = [call[1]["where"] for call in mock_log.call_args_list]
        self.assertIn("instant_sharing.unix_socket_server.start", log_wheres)
        self.assertIn("instant_sharing.unix_socket_server.stop", log_wheres)
        stop_call = next(
            call for call in mock_log.call_args_list
            if call[1]["where"] == "instant_sharing.unix_socket_server.stop"
        )
        self.assertTrue(stop_call[1]["attributes"]["instant_share.socket_removed"])

    @patch("dt_image_search.instant_sharing.unix_socket_server.add_span")
    @patch("dt_image_search.instant_sharing.unix_socket_server.log")
    def test_start_failure_on_stale_unlink_emits_error_log(self, mock_log, mock_span) -> None:
        self._mock_span(mock_span)
        with tempfile.TemporaryDirectory() as tmp:
            # A directory at the socket path makes unlink() fail deterministically.
            socket_path = Path(tmp) / "is.sock"
            socket_path.mkdir()
            server = UnixSocketHttpServer(
                request_handler=lambda body: {},
                socket_path=socket_path,
            )
            self.assertFalse(server.start())

        error_calls = [
            call for call in mock_log.call_args_list if call[0][0] == "error"
        ]
        self.assertTrue(error_calls)
        self.assertEqual(
            error_calls[0][1]["error_type"],
            "unix_socket_server.stale_unlink_failed",
        )

    @patch("dt_image_search.instant_sharing.unix_socket_server.add_span")
    @patch("dt_image_search.instant_sharing.unix_socket_server.log")
    def test_start_failure_without_handler_emits_error_log(self, mock_log, mock_span) -> None:
        self._mock_span(mock_span)
        with tempfile.TemporaryDirectory() as tmp:
            server = UnixSocketHttpServer(
                request_handler=None,
                socket_path=Path(tmp) / "is.sock",
            )
            self.assertFalse(server.start())

        error_calls = [
            call for call in mock_log.call_args_list if call[0][0] == "error"
        ]
        self.assertTrue(error_calls)
        self.assertEqual(
            error_calls[0][1]["error_type"],
            "unix_socket_server.no_request_handler",
        )


class QRTriggerTelemetryTests(unittest.TestCase):
    def _mock_span(self, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=MagicMock())
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

    @patch("dt_image_search.instant_sharing.qr_trigger_handler.add_span")
    @patch("dt_image_search.instant_sharing.qr_trigger_handler.log")
    def test_handle_trigger_success_emits_span_and_correlation_log(
        self, mock_log, mock_span
    ) -> None:
        self._mock_span(mock_span)
        handler = QRTriggerHandler()
        response = handler.handle_trigger({"type": "text", "content": "hello"})

        self.assertEqual(response.get("status"), "stashed")
        span_names = [call[0][0] for call in mock_span.call_args_list]
        self.assertIn("instant_share.qr_trigger.request", span_names)

        accepted_calls = [
            call for call in mock_log.call_args_list
            if call[1].get("attributes", {}).get("instant_share.stash_id")
        ]
        self.assertTrue(accepted_calls)
        self.assertEqual(
            accepted_calls[0][1]["attributes"]["instant_share.stash_id"],
            response["stash_id"],
        )
        self.assertEqual(
            accepted_calls[0][1]["attributes"]["instant_share.session_id"],
            response["session_id"],
        )

    @patch("dt_image_search.instant_sharing.qr_trigger_handler.add_span")
    @patch("dt_image_search.instant_sharing.qr_trigger_handler.log")
    def test_handle_trigger_rejection_emits_warning(self, mock_log, mock_span) -> None:
        self._mock_span(mock_span)
        handler = QRTriggerHandler()
        response = handler.handle_trigger({"type": "video"})

        self.assertEqual(response.get("_status"), 400)
        severities = [call[0][0] for call in mock_log.call_args_list]
        self.assertIn("warning", severities)


class AgentHeartbeatTelemetryTests(unittest.TestCase):
    @patch("dt_image_search.scripts.instant_share_agent_main.log")
    def test_heartbeat_rate_limits_and_reports_socket_state(self, mock_log) -> None:
        heartbeat = _AgentHeartbeat()
        runtime = MagicMock()
        runtime.unix_socket_server.socket_path = Path("/nonexistent/is.sock")
        runtime.unix_socket_server.is_running = True
        heartbeat.attach(runtime)

        heartbeat()  # first call emits
        heartbeat()  # immediate second call is rate-limited

        self.assertEqual(mock_log.call_count, 1)
        attributes = mock_log.call_args[1]["attributes"]
        self.assertTrue(attributes["instant_share.unix_socket_running"])
        self.assertFalse(attributes["instant_share.socket_exists"])
        self.assertTrue(attributes["instant_share.uptime_seconds"] >= 0)


if __name__ == "__main__":
    unittest.main()