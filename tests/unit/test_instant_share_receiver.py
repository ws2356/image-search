import os
import sys
import threading
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import DownloadedTextPayload, InstantShareMetadata, PayloadClass, TargetIntent, TrustMode
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.orchestrator import (
    INSTANT_SHARE_LIFECYCLE_EVENT,
    InstantShareReceiverOrchestrator,
    TrustHandshakeRequest,
)
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.tools.dts_event_bus import default_bus


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
        return {
            "mobile_dh_public_key": "mobile-pub-key",
            "mobile_nonce": "mobile-nonce",
            "kdf_context": "ctx-001",
        }

    def trust_apply(self, **kwargs):
        self.calls.append(("trust_apply", kwargs))
        return {"apply_status": "accepted"}

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
        return DownloadedTextPayload(metadata=metadata, text_utf8="shared from ios")

    def report_delivery_result(self, **kwargs):
        self.calls.append(("report_delivery_result", kwargs))
        return {"ack": True}


class _TimeoutingClient(_StubClient):
    def download_text_payload(self, **kwargs):
        self.calls.append(("download_text_payload", kwargs))
        raise InstantShareError(
            error_code=__import__("dt_image_search.instant_sharing.contracts", fromlist=["ErrorCode"]).ErrorCode.TRANSFER_TIMEOUT,
            message="download timed out",
            correlation_id=str(uuid.uuid4()),
        )


class _ParallelTrustClient(_StubClient):
    def __init__(self):
        super().__init__()
        self.apply_started = threading.Event()
        self.confirm_started = threading.Event()
        self.allow_apply_complete = threading.Event()

    def trust_apply(self, **kwargs):
        self.calls.append(("trust_apply", kwargs))
        self.apply_started.set()
        if not self.allow_apply_complete.wait(timeout=1.0):
            raise TimeoutError("trust_apply did not observe trust_confirm in time")
        return {"apply_status": "accepted"}

    def trust_confirm(self, **kwargs):
        self.calls.append(("trust_confirm", kwargs))
        self.confirm_started.set()
        self.allow_apply_complete.set()
        return {"mobile_public_key_pem": "mobile-public-key", "trust_status": "trusted"}


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
    def test_first_share_text_receive_emits_lifecycle_events(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        client = _StubClient()
        connection_config = _connection_config()
        received_events = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        session = orchestrator.handle_connection_config(connection_config)
        orchestrator.complete_trust(
            session_id=session.connection_config.session_id,
            client=client,
            correlation_id=connection_config.correlation_id,
            request=TrustHandshakeRequest(
                pc_dh_public_key="pc-dh-public-key",
                pc_nonce="pc-nonce",
                pc_public_key_pem="desktop-public-key",
            ),
        )
        downloaded_payload = orchestrator.receive_payload(
            session_id=session.connection_config.session_id,
            client=client,
            correlation_id=connection_config.correlation_id,
            requires_signature=False,
        )

        self.assertEqual(downloaded_payload.text_utf8, "shared from ios")
        self.assertEqual(clipboard.texts, ["shared from ios"])
        self.assertEqual(
            [event["state"] for event in received_events],
            ["queued", "negotiating", "transferring", "delivering", "done"],
        )
        self.assertEqual(client.calls[0][0], "trust_handshake")
        self.assertEqual({client.calls[1][0], client.calls[2][0]}, {"trust_apply", "trust_confirm"})
        self.assertEqual([call[0] for call in client.calls[3:]], ["download_text_payload", "report_delivery_result"])

    def test_transfer_timeout_maps_session_to_timed_out(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        client = _TimeoutingClient()
        connection_config = _connection_config()
        received_events = []
        subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)

        session = orchestrator.handle_connection_config(connection_config)

        with self.assertRaises(InstantShareError) as exc_info:
            orchestrator.receive_payload(
                session_id=session.connection_config.session_id,
                client=client,
                correlation_id=connection_config.correlation_id,
                requires_signature=False,
            )

        self.assertEqual(exc_info.exception.error_code.value, "TRANSFER_TIMEOUT")
        self.assertEqual(
            [event["state"] for event in received_events],
            ["queued", "transferring", "timed_out"],
        )

    def test_complete_trust_runs_apply_and_confirm_in_parallel(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
        orchestrator = InstantShareReceiverOrchestrator(
            session_registry=InstantShareSessionRegistry(),
            delivery_service=delivery_service,
        )
        client = _ParallelTrustClient()
        connection_config = _connection_config()

        session = orchestrator.handle_connection_config(connection_config)

        trust_result: dict[str, object] = {}
        trust_error: list[BaseException] = []

        def _run_complete_trust() -> None:
            try:
                trust_result.update(
                    orchestrator.complete_trust(
                        session_id=session.connection_config.session_id,
                        client=client,
                        correlation_id=connection_config.correlation_id,
                        request=TrustHandshakeRequest(
                            pc_dh_public_key="pc-dh-public-key",
                            pc_nonce="pc-nonce",
                            pc_public_key_pem="desktop-public-key",
                        ),
                    )
                )
            except BaseException as exc:
                trust_error.append(exc)

        worker = threading.Thread(target=_run_complete_trust, daemon=True)
        worker.start()

        self.assertTrue(client.apply_started.wait(timeout=1.0))
        self.assertTrue(client.confirm_started.wait(timeout=1.0))
        worker.join(timeout=1.0)

        self.assertFalse(worker.is_alive())
        self.assertEqual(trust_error, [])
        self.assertEqual(trust_result["trust_status"], "trusted")

    def test_abort_session_transitions_to_aborted(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)
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
        orchestrator._session_registry.transition(session.connection_config.session_id, __import__("dt_image_search.instant_sharing.contracts", fromlist=["SessionState"]).SessionState.TRANSFERRING)
        aborted = orchestrator.abort_session(session_id=session.connection_config.session_id)

        self.assertEqual(aborted.state.value, "aborted")
        self.assertEqual(received_events[-1]["state"], "aborted")
        self.assertEqual(received_events[-1]["error_code"], "USER_ABORTED")


if __name__ == "__main__":
    unittest.main()