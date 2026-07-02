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
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator
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

    def test_transfer_limit_exceeded_error_code(self):
        """TRANSFER_LIMIT_EXCEEDED error code is defined and has correct value."""
        from dt_image_search.instant_sharing.contracts import ErrorCode
        self.assertEqual(ErrorCode.TRANSFER_LIMIT_EXCEEDED.value, "TRANSFER_LIMIT_EXCEEDED")


class TestOrchestratorBatchLifecycle(unittest.TestCase):
    """Test that orchestrator defers delivery until all batch images received."""

    def setUp(self):
        self.session_registry = InstantShareSessionRegistry()
        self.delivery_service = InstantShareDeliveryService()
        self.orchestrator = InstantShareReceiverOrchestrator(
            session_registry=self.session_registry,
            delivery_service=self.delivery_service,
        )
        self.session_id = str(uuid.uuid4())
        self.correlation_id = str(uuid.uuid4())
        # Create a session first
        config = _config(session_id=self.session_id, payload_class="image")
        self.session_registry.bootstrap(config)

    def test_batch_not_complete_after_first_image(self):
        """handle_transfer_received returns False when batch not complete."""
        batch_complete = self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
            image_count=5,
        )
        self.assertFalse(batch_complete)
        session = self.session_registry.get_session(self.session_id)
        self.assertEqual(session.image_count, 5)
        self.assertEqual(session.received_count, 1)

    def test_batch_complete_after_last_image(self):
        """handle_transfer_received returns True when all images received."""
        # First 4 images
        self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
            image_count=5,
        )
        for _ in range(3):
            self.orchestrator.handle_transfer_received(
                session_id=self.session_id,
                correlation_id=self.correlation_id,
            )
        # 5th image — should be complete
        batch_complete = self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
        )
        self.assertTrue(batch_complete)
        session = self.session_registry.get_session(self.session_id)
        self.assertEqual(session.image_count, 5)
        self.assertEqual(session.received_count, 5)

    def test_delivery_deferred_when_batch_in_progress(self):
        """handle_delivery_complete does not transition when batch incomplete."""
        self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
            image_count=3,
        )
        # received_count=1, image_count=3 — not complete
        self.orchestrator.handle_delivery_complete(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
        )
        # Session should still be in TRANSFERRING, not DELIVERING or DONE
        session = self.session_registry.get_session(self.session_id)
        self.assertEqual(session.state, SessionState.TRANSFERRING)

    def test_delivery_proceeds_when_single_image(self):
        """handle_delivery_complete transitions for single image (no batch)."""
        self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
        )
        self.orchestrator.handle_delivery_complete(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
        )
        session = self.session_registry.get_session(self.session_id)
        self.assertEqual(session.state, SessionState.DONE)

    def test_image_count_only_set_on_first_request(self):
        """image_count is not overwritten on subsequent transfer calls."""
        self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
            image_count=5,
        )
        # Second call with different image_count — should be ignored
        self.orchestrator.handle_transfer_received(
            session_id=self.session_id,
            correlation_id=self.correlation_id,
            image_count=10,
        )
        session = self.session_registry.get_session(self.session_id)
        self.assertEqual(session.image_count, 5)  # Still 5, not 10


if __name__ == "__main__":
    unittest.main()