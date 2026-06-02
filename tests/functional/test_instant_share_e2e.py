"""End-to-end integration tests for the instant-share flow.

Exercises the full protocol path against a mock mobile server with real crypto:
- DH key exchange + AES-GCM trust session encryption
- Payload download (text and image)
- Delivery to clipboard and file
- Delivery result reporting
"""

import os
import sys
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    DeliveryResult,
    DeliveryTargetResult,
    InstantShareMetadata,
    PayloadClass,
    SessionState,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.http_client import (
    InstantShareHttpClient,
    RetryPolicy,
    SessionRequestSigner,
)
from dt_image_search.instant_sharing.orchestrator import (
    INSTANT_SHARE_LIFECYCLE_EVENT,
    InstantShareReceiverOrchestrator,
    TrustHandshakeRequest,
)
from dt_image_search.instant_sharing.security import (
    PersistentEd25519SessionSigner,
    X25519TrustSessionKeyResolver,
)
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_crypto import AesGcmTrustSessionProtector
from dt_image_search.tools.dts_event_bus import default_bus

from tests.functional.mock_mobile_instant_share_server import MockMobileInstantShareServer


class _InMemoryClipboardWriter:
    def __init__(self) -> None:
        self.texts: list[str] = []
        self.image_calls: list[bytes] = []

    def write_text(self, text: str) -> None:
        self.texts.append(text)

    def write_image_bytes(self, image_bytes: bytes) -> None:
        self.image_calls.append(image_bytes)


class TestInstantShareEndToEnd(unittest.TestCase):
    """End-to-end integration tests exercising the full instant-share protocol."""

    def setUp(self) -> None:
        self._temp_dir = tempfile.mkdtemp(prefix="instant_share_e2e_")
        self.addCleanup(lambda: os.system(f"rm -rf {self._temp_dir}"))
        self._clipboard = _InMemoryClipboardWriter()

    def _make_connection_config(
        self,
        *,
        port: int,
        payload_class: str = "text",
        target_intent: str = "clipboard_only",
        trust_mode: str = "first_share",
    ) -> ConnectionConfig:
        return ConnectionConfig.from_dict({
            "session_id": str(uuid.uuid4()),
            "mobile_port": port,
            "mobile_ip_list": ["127.0.0.1"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": payload_class,
            "target_intent": target_intent,
            "trust_mode": trust_mode,
        })

    def _make_signer(self) -> SessionRequestSigner:
        key_path = Path(self._temp_dir) / "signing-key.pem"
        return PersistentEd25519SessionSigner(key_path)

    def _make_pc_identity(self) -> tuple[str, str]:
        """Generate PC identity: (signer, public_key_pem)."""
        signer = self._make_signer()
        # We need the public key PEM for trust/confirm
        from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
        key_path = Path(self._temp_dir) / "signing-key.pem"
        # Re-read the public key from the private key
        from cryptography.hazmat.primitives import serialization as ser
        private_key = ser.load_pem_private_key(key_path.read_bytes(), password=None)
        public_key_pem = private_key.public_key().public_bytes(
            Encoding.PEM, PublicFormat.SubjectPublicKeyInfo,
        ).decode("utf-8")
        return signer, public_key_pem

    def test_text_to_clipboard_end_to_end(self) -> None:
        """Full first-share flow: trust handshake -> payload download -> clipboard delivery."""
        shared_text = "Hello from my iPhone!"
        server = MockMobileInstantShareServer(shared_text=shared_text)
        server.start()
        self.addCleanup(server.stop)

        connection_config = self._make_connection_config(port=server.port)
        signer, pc_public_key_pem = self._make_pc_identity()

        # Create PC-side components
        dh_resolver = X25519TrustSessionKeyResolver()
        trust_protector = AesGcmTrustSessionProtector(session_key_resolver=dh_resolver)

        client = InstantShareHttpClient(
            connection_config=connection_config,
            device_id="test-pc-001",
            session_signer=signer,
            trust_session_protector=trust_protector,
            retry_policy=RetryPolicy(max_attempts=1),
        )

        session_registry = InstantShareSessionRegistry()
        delivery_service = InstantShareDeliveryService(clipboard_writer=self._clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
        )

        received_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        # Step 1: Bootstrap session (simulates BLE ConnectionConfig write)
        session = orchestrator.handle_connection_config(connection_config)
        session_id = session.connection_config.session_id
        correlation_id = connection_config.correlation_id

        # Step 2: Complete trust (DH handshake + parallel apply/confirm)
        handshake_request = dh_resolver.handshake_request_payload()
        trust_result = orchestrator.complete_trust(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            request=TrustHandshakeRequest(
                pc_dh_public_key=handshake_request["pc_dh_public_key"],
                pc_nonce=handshake_request["pc_nonce"],
                pc_public_key_pem=pc_public_key_pem,
            ),
        )
        self.assertEqual(trust_result["trust_status"], "trusted")
        self.assertIn("mobile_public_key_pem", trust_result)

        # Step 3: Receive payload (download + deliver)
        downloaded = orchestrator.receive_payload(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            requires_signature=True,
        )

        # Verify payload was downloaded and delivered
        self.assertEqual(downloaded.text_utf8, shared_text)
        self.assertEqual(self._clipboard.texts, [shared_text])

        # Verify lifecycle events
        states = [event["state"] for event in received_events]
        self.assertEqual(
            states,
            ["queued", "negotiating", "transferring", "delivering", "done"],
        )

        # Verify delivery result was reported
        self.assertEqual(len(server.delivery_results), 1)
        result = server.delivery_results[0]
        self.assertEqual(result["state"], "done")
        self.assertTrue(result["target_result"]["clipboard_written"])

    def test_image_to_file_end_to_end(self) -> None:
        """Full first-share flow with image payload delivered to file."""
        image_bytes = b"\x89PNG\r\n\x1a\n" + os.urandom(128)
        server = MockMobileInstantShareServer(
            shared_image_bytes=image_bytes,
            shared_image_filename="photo.jpg",
            shared_image_content_type="image/jpeg",
        )
        server.start()
        self.addCleanup(server.stop)

        delivery_dir = Path(self._temp_dir) / "deliveries"
        delivery_dir.mkdir()

        connection_config = self._make_connection_config(
            port=server.port,
            payload_class="image",
            target_intent="clipboard_or_file",
        )
        signer, pc_public_key_pem = self._make_pc_identity()

        dh_resolver = X25519TrustSessionKeyResolver()
        trust_protector = AesGcmTrustSessionProtector(session_key_resolver=dh_resolver)

        client = InstantShareHttpClient(
            connection_config=connection_config,
            device_id="test-pc-002",
            session_signer=signer,
            trust_session_protector=trust_protector,
            retry_policy=RetryPolicy(max_attempts=1),
        )

        session_registry = InstantShareSessionRegistry()
        delivery_service = InstantShareDeliveryService(
            clipboard_writer=self._clipboard,
            image_delivery_mode="file",
            downloads_dir=delivery_dir,
        )
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
        )

        received_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        # Bootstrap + trust
        session = orchestrator.handle_connection_config(connection_config)
        session_id = session.connection_config.session_id
        correlation_id = connection_config.correlation_id

        handshake_request = dh_resolver.handshake_request_payload()
        orchestrator.complete_trust(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            request=TrustHandshakeRequest(
                pc_dh_public_key=handshake_request["pc_dh_public_key"],
                pc_nonce=handshake_request["pc_nonce"],
                pc_public_key_pem=pc_public_key_pem,
            ),
        )

        # Receive image payload
        downloaded = orchestrator.receive_payload(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            requires_signature=True,
        )

        # Verify image was downloaded and written to file
        self.assertEqual(downloaded.image_bytes, image_bytes)
        self.assertEqual(downloaded.filename, "photo.jpg")
        self.assertEqual(downloaded.content_type, "image/jpeg")

        # Verify file was written to delivery directory
        written_files = list(delivery_dir.glob("photo*"))
        self.assertEqual(len(written_files), 1)
        self.assertEqual(written_files[0].read_bytes(), image_bytes)

        # Verify lifecycle events
        states = [event["state"] for event in received_events]
        self.assertEqual(
            states,
            ["queued", "negotiating", "transferring", "delivering", "done"],
        )

        # Verify delivery result
        self.assertEqual(len(server.delivery_results), 1)
        result = server.delivery_results[0]
        self.assertEqual(result["state"], "done")
        self.assertEqual(result["target_result"]["files_written_count"], 1)

    def test_text_to_clipboard_with_trusted_direct_skip_negotiation(self) -> None:
        """Trusted-direct flow skips trust negotiation when DeviceSignature is verified."""
        shared_text = "Trusted direct share!"
        server = MockMobileInstantShareServer(shared_text=shared_text)
        server.start()
        self.addCleanup(server.stop)

        connection_config = self._make_connection_config(
            port=server.port,
            trust_mode="trusted_direct",
        )
        signer, _ = self._make_pc_identity()

        client = InstantShareHttpClient(
            connection_config=connection_config,
            device_id="test-pc-003",
            session_signer=signer,
            pinned_mobile_public_key_pem=server.public_key_pem_for_tls_pin,
            retry_policy=RetryPolicy(max_attempts=1),
        )

        session_registry = InstantShareSessionRegistry()
        delivery_service = InstantShareDeliveryService(clipboard_writer=self._clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
        )

        received_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        # Bootstrap session
        session = orchestrator.handle_connection_config(connection_config)
        session_id = session.connection_config.session_id

        # Skip trust, go directly to transfer (trusted-direct path)
        downloaded = orchestrator.receive_payload(
            session_id=session_id,
            client=client,
            correlation_id=connection_config.correlation_id,
            requires_signature=True,
        )

        self.assertEqual(downloaded.text_utf8, shared_text)
        self.assertEqual(self._clipboard.texts, [shared_text])

        # Should go: queued -> transferring -> delivering -> done (no negotiating)
        states = [event["state"] for event in received_events]
        self.assertEqual(
            states,
            ["queued", "transferring", "delivering", "done"],
        )

    def test_delivery_result_reports_success_to_server(self) -> None:
        """Delivery result is reported back to the mobile server."""
        server = MockMobileInstantShareServer(shared_text="test")
        server.start()
        self.addCleanup(server.stop)

        connection_config = self._make_connection_config(port=server.port)
        signer, pc_public_key_pem = self._make_pc_identity()

        dh_resolver = X25519TrustSessionKeyResolver()
        trust_protector = AesGcmTrustSessionProtector(session_key_resolver=dh_resolver)

        client = InstantShareHttpClient(
            connection_config=connection_config,
            device_id="test-pc-004",
            session_signer=signer,
            trust_session_protector=trust_protector,
            retry_policy=RetryPolicy(max_attempts=1),
        )

        session_registry = InstantShareSessionRegistry()
        delivery_service = InstantShareDeliveryService(clipboard_writer=self._clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=session_registry,
            delivery_service=delivery_service,
        )

        session = orchestrator.handle_connection_config(connection_config)
        session_id = session.connection_config.session_id
        correlation_id = connection_config.correlation_id

        handshake_request = dh_resolver.handshake_request_payload()
        orchestrator.complete_trust(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            request=TrustHandshakeRequest(
                pc_dh_public_key=handshake_request["pc_dh_public_key"],
                pc_nonce=handshake_request["pc_nonce"],
                pc_public_key_pem=pc_public_key_pem,
            ),
        )

        orchestrator.receive_payload(
            session_id=session_id,
            client=client,
            correlation_id=correlation_id,
            requires_signature=True,
        )

        # Verify the server received the delivery result
        self.assertEqual(len(server.delivery_results), 1)
        dr = server.delivery_results[0]
        self.assertEqual(dr["state"], "done")
        self.assertTrue(dr["target_result"]["clipboard_written"])
        self.assertEqual(dr["target_result"]["files_written_count"], 0)


if __name__ == "__main__":
    unittest.main()
