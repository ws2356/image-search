import os
import sys
import unittest
import uuid
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    DownloadedTextPayload,
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.orchestrator import (
    InstantShareReceiverOrchestrator,
    TrustHandshakeRequest,
    _session_attributes,
)
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


class _ClipboardRecorder:
    def __init__(self):
        self.texts = []

    def write_text(self, text: str) -> None:
        self.texts.append(text)

    def write_image_bytes(self, image_bytes: bytes) -> None:
        raise AssertionError("Image delivery is not expected in this test.")


class _StubClient:
    def __init__(self):
        self.calls = []

    def trust_handshake(self, **kwargs):
        self.calls.append(("trust_handshake", kwargs))
        return {"mobile_dh_public_key": "m", "mobile_nonce": "n", "kdf_context": "c"}

    def trust_apply(self, **kwargs):
        self.calls.append(("trust_apply", kwargs))
        return "123456"

    def trust_confirm(self, **kwargs):
        self.calls.append(("trust_confirm", kwargs))
        return {"mobile_public_key_pem": "mobile-public-key", "trust_status": "trusted"}

    def download_text_payload(self, **kwargs):
        self.calls.append(("download_text_payload", kwargs))
        metadata = InstantShareMetadata(
            payload_class=PayloadClass.TEXT,
            target_intent=TargetIntent.CLIPBOARD_ONLY,
            trust_mode=TrustMode.FIRST_SHARE,
        )
        return DownloadedTextPayload(metadata=metadata, text_utf8="hello")

    def report_delivery_result(self, **kwargs):
        self.calls.append(("report_delivery_result", kwargs))
        return {"ack": True}


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
    @patch("dt_image_search.instant_sharing.orchestrator.add_span")
    @patch("dt_image_search.instant_sharing.orchestrator.log")
    def test_handle_connection_config_emits_span_and_log(self, mock_log, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=None)
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        config = _connection_config()
        orchestrator.handle_connection_config(config)

        mock_span.assert_called_once()
        span_name = mock_span.call_args[0][0]
        self.assertEqual(span_name, "instant_share.session.bootstrap")

        mock_log.assert_called_once()
        log_kwargs = mock_log.call_args
        self.assertEqual(log_kwargs[0][0], "info")
        self.assertIn("accepted", log_kwargs[1]["message"].lower())

    @patch("dt_image_search.instant_sharing.orchestrator.add_span")
    @patch("dt_image_search.instant_sharing.orchestrator.log")
    def test_receive_payload_emits_span_and_log(self, mock_log, mock_span) -> None:
        mock_span.return_value.__enter__ = MagicMock(return_value=None)
        mock_span.return_value.__exit__ = MagicMock(return_value=False)

        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        client = _StubClient()
        config = _connection_config()

        orchestrator.handle_connection_config(config)
        orchestrator.receive_payload(
            session_id=config.session_id,
            client=client,
            correlation_id=config.correlation_id,
            requires_signature=False,
        )

        span_calls = mock_span.call_args_list
        span_names = [call[0][0] for call in span_calls]
        self.assertIn("instant_share.payload.receive", span_names)

        log_messages = [call[1].get("message", "") for call in mock_log.call_args_list]
        self.assertTrue(any("downloaded" in msg.lower() for msg in log_messages))
        self.assertTrue(any("delivery" in msg.lower() for msg in log_messages))


if __name__ == "__main__":
    unittest.main()
