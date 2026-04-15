import hashlib
import json
import errno
import os
from pathlib import Path
import socket
import sys
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.contracts import (
    MobileTransportKind,
    MobileTransportResponse,
    TransferAssetUploadPayload,
)
from dt_image_search.mobile.transport.router import MobileTransportRouter
from dt_image_search.mobile.transport.usb_tunnel import (
    UsbConnectedDevice,
    UsbTunnelConnectError,
    UsbTunnelUnavailableError,
)
from dt_image_search.mobile.transport.usb_ws_adapter import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    UsbBootstrapConfig,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
    _default_websocket_connect,
    iter_usb_probe_ports,
)


class _FakeUsbTunnelProvider:
    def __init__(
        self,
        *,
        devices: tuple[UsbConnectedDevice, ...] = tuple(),
        connectable_ports: set[tuple[str, int]] | None = None,
        unavailable_error: str | None = None,
    ):
        self._devices = devices
        self._connectable_ports = connectable_ports or set()
        self._unavailable_error = unavailable_error
        self.probe_calls: list[tuple[str, int]] = []
        self.connect_calls: list[tuple[str, int]] = []

    def list_usb_devices(self) -> tuple[UsbConnectedDevice, ...]:
        if self._unavailable_error is not None:
            raise UsbTunnelUnavailableError(self._unavailable_error)
        return self._devices

    def probe_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> bool:
        self.probe_calls.append((udid, port))
        return (udid, port) in self._connectable_ports

    def connect_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> socket.socket:
        self.connect_calls.append((udid, port))
        if (udid, port) not in self._connectable_ports:
            raise UsbTunnelConnectError(f"Unable to connect to {udid}:{port}")
        return socket.socket(socket.AF_INET, socket.SOCK_STREAM)


class _FakeWebSocketConnection:
    def __init__(
        self,
        incoming_messages: list[str | bytes] | None = None,
        *,
        one_time_passcode: str = "482913",
    ):
        self._incoming_messages = list(incoming_messages or [])
        self._one_time_passcode = one_time_passcode
        self.sent_messages: list[str] = []
        self.challenge_requests: list[dict[str, object]] = []
        self.closed = False

    def recv(self, timeout: float | None = None) -> str | bytes:
        if self.closed:
            raise RuntimeError("WebSocket connection closed.")
        if self._incoming_messages:
            return self._incoming_messages.pop(0)
        raise TimeoutError()

    def send(self, message: str) -> None:
        if self.closed:
            raise RuntimeError("WebSocket connection closed.")
        try:
            parsed_message = json.loads(message)
        except json.JSONDecodeError:
            self.sent_messages.append(message)
            return
        if not isinstance(parsed_message, dict):
            self.sent_messages.append(message)
            return
        if parsed_message.get("operation") != "transport.auth.challenge":
            self.sent_messages.append(message)
            return
        request_id = parsed_message.get("request_id")
        body = parsed_message.get("body")
        if not isinstance(request_id, str) or not isinstance(body, dict):
            self.sent_messages.append(message)
            return
        challenge_sid = body.get("sid")
        challenge_rand = body.get("rand")
        if not isinstance(challenge_sid, str) or not challenge_sid.strip():
            self.sent_messages.append(message)
            return
        if not isinstance(challenge_rand, str) or not challenge_rand.strip():
            self.sent_messages.append(message)
            return
        self.challenge_requests.append(dict(body))
        challenge_digest = hashlib.sha256(
            f"{self._one_time_passcode}{challenge_rand}".encode("utf-8")
        ).hexdigest()
        challenge_response = json.dumps(
            {
                "schema": "dtis.mobile-transport.v1",
                "request_id": request_id,
                "status_code": 200,
                "body": {
                    "schema": "dtis.mobile-transport.v1",
                    "status": "accepted",
                    "proof": challenge_digest,
                },
            }
        )
        self._incoming_messages.insert(0, challenge_response)

    def close(self, code: int = 1000, reason: str = "") -> None:
        self.closed = True


class _FakeWebSocketConnector:
    def __init__(self, connection: _FakeWebSocketConnection):
        self._connection = connection
        self.calls: list[dict[str, object]] = []

    def __call__(self, **kwargs: object) -> _FakeWebSocketConnection:
        self.calls.append(kwargs)
        return self._connection


class TestUsbWebSocketTransportAdapter(unittest.TestCase):
    def setUp(self):
        self._router = MobileTransportRouter()
        self._adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
        )

    def test_default_websocket_connect_retries_with_unix_mode_for_non_tcp_socket(self):
        sentinel_connection = _FakeWebSocketConnection()
        observed_kwargs: list[dict[str, object]] = []
        fake_tunnel_socket = object()

        def _fake_websocket_connect(**kwargs: object):
            observed_kwargs.append(dict(kwargs))
            if kwargs.get("unix", False):
                return sentinel_connection
            raise OSError(errno.EOPNOTSUPP, "Operation not supported on socket")

        with patch(
            "dt_image_search.mobile.transport.usb_ws_adapter.websocket_connect",
            new=_fake_websocket_connect,
        ):
            connected = _default_websocket_connect(
                uri="ws://127.0.0.1:55032",
                sock=fake_tunnel_socket,
                proxy=None,
            )

        self.assertIs(connected, sentinel_connection)
        self.assertEqual(len(observed_kwargs), 2)
        self.assertFalse(observed_kwargs[0].get("unix", False))
        self.assertTrue(observed_kwargs[1].get("unix", False))

    def test_start_requires_bootstrap_config(self):
        with self.assertRaises(RuntimeError):
            self._adapter.start()

    def test_build_and_verify_auth_digest(self):
        self._adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
            )
        )
        digest = self._adapter.build_auth_digest("rand-xyz")
        self.assertTrue(self._adapter.verify_auth_digest(rand="rand-xyz", provided_digest=digest))
        self.assertFalse(self._adapter.verify_auth_digest(rand="rand-abc", provided_digest=digest))

    def test_dispatch_text_envelope_routes_registered_operation(self):
        observed_contexts = []

        def handler(request):
            observed_contexts.append(request.context)
            return MobileTransportResponse(
                status_code=200,
                payload={"schema": "dtis.mobile-transfer.v1", "status": "accepted"},
            )

        self._router.register("transfer.start", handler)
        response = self._adapter.dispatch_text_envelope(
            (
                '{"schema":"dtis.mobile-transport.v1","operation":"transfer.start",'
                '"request_id":"req-001","body":{"total_assets":3}}'
            ),
            remote_address="usb://device-001",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.payload["status"], "accepted")
        self.assertEqual(len(observed_contexts), 1)
        self.assertEqual(observed_contexts[0].transport, MobileTransportKind.USB_WEBSOCKET)
        self.assertEqual(observed_contexts[0].request_id, "req-001")
        self.assertEqual(observed_contexts[0].remote_address, "usb://device-001")

    def test_dispatch_text_envelope_rejects_unknown_operation(self):
        response = self._adapter.dispatch_text_envelope(
            '{"schema":"dtis.mobile-transport.v1","operation":"transfer.unknown","request_id":"req-unknown","body":{}}'
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.payload["schema"], MOBILE_TRANSPORT_ENVELOPE_SCHEMA)
        self.assertEqual(response.payload["status"], "rejected")
        self.assertIn("does not support", response.payload["message"])

    def test_dispatch_text_envelope_rejects_transfer_asset_without_stream_state(self):
        response = self._adapter.dispatch_text_envelope(
            json.dumps(
                {
                    "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                    "operation": "transfer.asset",
                    "request_id": "req-asset-001",
                    "body": {
                        "schema": "dtis.mobile-transfer.v1",
                        "session_id": "session-001",
                        "asset_id": "asset-001",
                    },
                }
            ),
            remote_address="usb://ios-001",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.payload["status"], "rejected")
        self.assertIn("stream_state", response.payload["message"])

    def test_state_transitions(self):
        provider = _FakeUsbTunnelProvider()
        websocket_connection = _FakeWebSocketConnection()
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
                fallback_port_window=20,
            )
        )
        self.assertEqual(adapter.state, UsbTransportState.CONFIGURED)
        adapter.start()
        self.assertTrue(
            self._wait_until(
                lambda: adapter.state == UsbTransportState.READY,
                timeout_seconds=0.6,
            )
        )
        adapter.stop()
        self.assertEqual(adapter.state, UsbTransportState.STOPPED)

    def test_start_marks_connected_when_usb_probe_succeeds(self):
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
            connectable_ports={("ios-001", 50213)},
        )
        websocket_connection = _FakeWebSocketConnection()
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
                fallback_port_window=3,
            )
        )

        adapter.start()

        self.assertTrue(
            self._wait_until(
                lambda: adapter.state == UsbTransportState.CONNECTED,
                timeout_seconds=1.2,
            )
        )
        self.assertEqual(adapter.state, UsbTransportState.CONNECTED)
        self.assertIsNotNone(adapter.active_tunnel_target)
        self.assertEqual(adapter.active_tunnel_target.device_udid, "ios-001")
        self.assertEqual(adapter.active_tunnel_target.remote_port, 50213)
        self.assertEqual(len(websocket_connection.challenge_requests), 1)
        self.assertEqual(websocket_connection.challenge_requests[0]["sid"], "session-001")
        self.assertTrue(isinstance(websocket_connection.challenge_requests[0]["rand"], str))
        self.assertNotIn("auth", websocket_connection.challenge_requests[0])
        self.assertEqual(provider.connect_calls, [("ios-001", 50213)])
        self.assertEqual(len(websocket_connector.calls), 1)
        self.assertEqual(
            provider.probe_calls,
            [
                ("ios-001", 50211),
                ("ios-001", 50212),
                ("ios-001", 50210),
                ("ios-001", 50213),
            ],
        )
        adapter.stop()

    def test_start_records_probe_error_when_no_port_is_reachable(self):
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
        )
        websocket_connection = _FakeWebSocketConnection()
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
                fallback_port_window=1,
            )
        )

        adapter.start()
        self.assertTrue(
            self._wait_until(
                lambda: adapter.last_probe_error is not None,
                timeout_seconds=1.0,
            )
        )

        self.assertEqual(adapter.state, UsbTransportState.READY)
        self.assertIsNone(adapter.active_tunnel_target)
        self.assertEqual(
            adapter.last_probe_error,
            "Desktop could not connect to any USB bootstrap port candidates.",
        )
        adapter.stop()

    def test_start_records_probe_error_when_provider_is_unavailable(self):
        provider = _FakeUsbTunnelProvider(unavailable_error="pymobiledevice3 not installed")
        websocket_connection = _FakeWebSocketConnection()
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
                fallback_port_window=1,
            )
        )

        adapter.start()
        self.assertTrue(
            self._wait_until(
                lambda: adapter.last_probe_error is not None,
                timeout_seconds=1.0,
            )
        )

        self.assertEqual(adapter.state, UsbTransportState.READY)
        self.assertEqual(adapter.last_probe_error, "pymobiledevice3 not installed")
        adapter.stop()

    def test_usb_websocket_loop_sends_correlated_response_envelopes(self):
        observed_contexts = []

        def handler(request):
            observed_contexts.append(request.context)
            return MobileTransportResponse(
                status_code=200,
                payload={"schema": "dtis.mobile-transfer.v1", "status": "accepted"},
            )

        self._router.register("transfer.start", handler)
        request_envelope = json.dumps(
            {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": "transfer.start",
                "request_id": "req-001",
                "body_schema": "dtis.mobile-transfer.v1",
                "body": {"total_assets": 3},
            }
        )
        websocket_connection = _FakeWebSocketConnection(incoming_messages=[request_envelope])
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
            connectable_ports={("ios-001", 50211)},
        )
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
            )
        )

        adapter.start()
        self.assertTrue(
            self._wait_until(
                lambda: len(websocket_connection.sent_messages) == 1,
                timeout_seconds=1.2,
            )
        )
        adapter.stop()

        self.assertEqual(len(observed_contexts), 1)
        self.assertEqual(observed_contexts[0].transport, MobileTransportKind.USB_WEBSOCKET)
        response_envelope = json.loads(websocket_connection.sent_messages[0])
        self.assertEqual(response_envelope["schema"], MOBILE_TRANSPORT_ENVELOPE_SCHEMA)
        self.assertEqual(response_envelope["request_id"], "req-001")
        self.assertEqual(response_envelope["status_code"], 200)
        self.assertEqual(response_envelope["body"]["status"], "accepted")

    def test_usb_websocket_loop_streams_transfer_asset_binary_frames(self):
        observed_upload: dict[str, object] = {}

        def handler(request):
            self.assertIsInstance(request.payload, TransferAssetUploadPayload)
            upload_payload = request.payload
            observed_upload["metadata"] = dict(upload_payload.metadata_payload)
            observed_upload["content_length"] = upload_payload.content_length
            self.assertIsNone(upload_payload.body_stream)
            self.assertIsNotNone(upload_payload.temp_file_path)
            observed_upload["content_sha1"] = upload_payload.content_sha1
            staged_path = Path(upload_payload.temp_file_path or "")
            observed_upload["body"] = staged_path.read_bytes()
            staged_path.unlink(missing_ok=True)
            return MobileTransportResponse(
                status_code=200,
                payload={"schema": "dtis.mobile-transfer.v1", "status": "stored"},
            )

        self._router.register("transfer.asset", handler)
        stream_start_envelope = json.dumps(
            {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": "transfer.asset",
                "request_id": "req-asset-001",
                "body_schema": "dtis.mobile-transfer.v1",
                "body": {
                    "stream_state": "start",
                    "chunk_size": 2 * 1024 * 1024,
                    "schema": "dtis.mobile-transfer.v1",
                    "session_id": "session-001",
                    "device_uuid": "ios-device-001",
                    "trust_key": "trust-key",
                    "asset_id": "asset-001",
                    "asset_version": "v1",
                    "sha1": "0123456789abcdef0123456789abcdef01234567",
                    "file_size": 11,
                    "filename": "asset.jpg",
                    "media_type": "image/jpeg",
                },
            }
        )
        stream_complete_envelope = json.dumps(
            {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": "transfer.asset",
                "request_id": "req-asset-001",
                "body_schema": "dtis.mobile-transfer.v1",
                "body": {
                    "stream_state": "complete",
                },
            }
        )
        websocket_connection = _FakeWebSocketConnection(
            incoming_messages=[
                stream_start_envelope,
                b"hello ",
                b"world",
                stream_complete_envelope,
            ]
        )
        websocket_connector = _FakeWebSocketConnector(websocket_connection)
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
            connectable_ports={("ios-001", 50211)},
        )
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
            websocket_connect_fn=websocket_connector,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
            )
        )

        adapter.start()
        self.assertTrue(
            self._wait_until(
                lambda: len(websocket_connection.sent_messages) == 1,
                timeout_seconds=1.2,
            )
        )
        adapter.stop()

        self.assertEqual(observed_upload["content_length"], 11)
        self.assertEqual(observed_upload["body"], b"hello world")
        self.assertEqual(observed_upload["content_sha1"], hashlib.sha1(b"hello world").hexdigest())
        self.assertEqual(observed_upload["metadata"]["asset_id"], "asset-001")
        self.assertNotIn("chunk_size", observed_upload["metadata"])
        response_envelope = json.loads(websocket_connection.sent_messages[0])
        self.assertEqual(response_envelope["request_id"], "req-asset-001")
        self.assertEqual(response_envelope["status_code"], 200)
        self.assertEqual(response_envelope["body"]["status"], "stored")

    def test_iter_usb_probe_ports_generates_symmetric_candidates(self):
        self.assertEqual(
            iter_usb_probe_ports(
                suggested_port=47000,
                fallback_port_window=3,
            ),
            (47000, 47001, 46999, 47002, 46998, 47003, 46997),
        )

    @staticmethod
    def _noop_log(*args, **kwargs):
        return None

    @staticmethod
    def _wait_until(predicate, *, timeout_seconds: float) -> bool:
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.01)
        return False


if __name__ == "__main__":
    unittest.main()
