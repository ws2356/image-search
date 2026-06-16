import json
import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    PayloadClass,
    SessionState,
)
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.instant_sharing.transfer_server import TransferHandler


def _config(session_id: str | None = None, payload_class: str = "text"):
    return ConnectionConfig.from_dict(
        {
            "session_id": session_id or str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": ["192.168.1.50"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": payload_class,
            "target_intent": "clipboard_only" if payload_class == "text" else "clipboard_or_file",
            "trust_mode": "first_share",
        }
    )


class TestTransferHandlerText(unittest.TestCase):
    def setUp(self):
        self.session_registry = InstantShareSessionRegistry()
        self.delivery_service = InstantShareDeliveryService()
        self.transfer_handler = TransferHandler(
            session_registry=self.session_registry,
            delivery_service=self.delivery_service,
        )
        self.trust_registry = TrustSessionRegistry()
        self.session_id = str(uuid.uuid4())
        self.correlation_id = str(uuid.uuid4())

    def test_receive_text_without_active_session_raises(self):
        with self.assertRaises(InstantShareError) as exc_info:
            self.transfer_handler.receive_text(
                session_id="nonexistent",
                correlation_id=self.correlation_id,
                body=b'{"text_utf8": "hello"}',
            )
        self.assertEqual(exc_info.exception.error_code.value, "SESSION_ID_MISMATCH")

    def test_receive_image_without_active_session_raises(self):
        with self.assertRaises(InstantShareError) as exc_info:
            self.transfer_handler.receive_image(
                session_id="nonexistent",
                correlation_id=self.correlation_id,
                body=b"\xff\xd8\xff\xe0",
                content_type="image/jpeg",
                filename="test.jpg",
            )
        self.assertEqual(exc_info.exception.error_code.value, "SESSION_ID_MISMATCH")

    def test_receive_text_with_empty_body_raises(self):
        config = _config(session_id=self.session_id, payload_class="text")
        self.session_registry.bootstrap(config)
        self.session_registry.transition(self.session_id, SessionState.NEGOTIATING)
        with self.assertRaises(InstantShareError) as exc_info:
            self.transfer_handler.receive_text(
                session_id=self.session_id,
                correlation_id=self.correlation_id,
                body=b"",
            )
        self.assertEqual(exc_info.exception.error_code.value, "PAYLOAD_UNREADABLE")

    def test_receive_text_with_missing_text_utf8_raises(self):
        config = _config(session_id=self.session_id, payload_class="text")
        self.session_registry.bootstrap(config)
        self.session_registry.transition(self.session_id, SessionState.NEGOTIATING)
        with self.assertRaises(InstantShareError) as exc_info:
            self.transfer_handler.receive_text(
                session_id=self.session_id,
                correlation_id=self.correlation_id,
                body=b'{"metadata": {}}',
            )
        self.assertEqual(exc_info.exception.error_code.value, "PAYLOAD_UNREADABLE")

    def test_receive_text_with_wrong_payload_class_raises(self):
        config = _config(session_id=self.session_id, payload_class="image")
        self.session_registry.bootstrap(config)
        self.session_registry.transition(self.session_id, SessionState.NEGOTIATING)
        with self.assertRaises(InstantShareError) as exc_info:
            self.transfer_handler.receive_text(
                session_id=self.session_id,
                correlation_id=self.correlation_id,
                body=b'{"text_utf8": "hello"}',
            )
        self.assertEqual(exc_info.exception.error_code.value, "DELIVERY_PATH_INVALID")


class TestNewErrorCodeConstants(unittest.TestCase):
    def test_session_not_found_error_code(self):
        from dt_image_search.instant_sharing.contracts import ErrorCode
        self.assertEqual(ErrorCode.SESSION_NOT_FOUND.value, "SESSION_NOT_FOUND")

    def test_trust_required_error_code(self):
        from dt_image_search.instant_sharing.contracts import ErrorCode
        self.assertEqual(ErrorCode.TRUST_REQUIRED.value, "TRUST_REQUIRED")

    def test_handshake_required_error_code(self):
        from dt_image_search.instant_sharing.contracts import ErrorCode
        self.assertEqual(ErrorCode.HANDSHAKE_REQUIRED.value, "HANDSHAKE_REQUIRED")


if __name__ == "__main__":
    unittest.main()