import hashlib
import json
import os
import socket
import sys
import threading
import time
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from websockets.exceptions import ConnectionClosed
from websockets.sync.server import ServerConnection, serve

from dt_image_search.mobile.transport.router import MobileTransportRouter
from dt_image_search.mobile.transport.usb_ws_adapter import (
    USB_AUTH_CHALLENGE_OPERATION,
    UsbBootstrapConfig,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
)
from dt_image_search.mobile.transport.usb_tunnel import (
    UsbConnectedDevice,
    UsbTunnelConnectError,
)


class _LoopbackUsbTunnelProvider:
    def __init__(self, *, device_udid: str, connect_port: int):
        self._device_udid = device_udid
        self._connect_port = connect_port
        self.probe_calls: list[tuple[str, int]] = []
        self.connect_calls: list[tuple[str, int]] = []

    def list_usb_devices(self) -> tuple[UsbConnectedDevice, ...]:
        return (UsbConnectedDevice(udid=self._device_udid),)

    def probe_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> bool:
        self.probe_calls.append((udid, port))
        return udid == self._device_udid and port == self._connect_port

    def connect_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> socket.socket:
        self.connect_calls.append((udid, port))
        if udid != self._device_udid or port != self._connect_port:
            raise UsbTunnelConnectError(f"Unable to connect to {udid}:{port}")
        return socket.create_connection(("127.0.0.1", self._connect_port), timeout=timeout_seconds)


class _MockMobileUsbRuntimeServer:
    def __init__(self, *, session_id: str, one_time_passcode: str):
        self._session_id = session_id
        self._one_time_passcode = one_time_passcode
        self._server = None
        self._thread: threading.Thread | None = None
        self._shutdown_event = threading.Event()
        self._ready_event = threading.Event()
        self._port = self._find_free_port()
        self.challenge_received = threading.Event()

    @property
    def port(self) -> int:
        return self._port

    def start(self) -> None:
        self._thread = threading.Thread(
            target=self._run_server,
            name="mock-mobile-usb-runtime",
            daemon=True,
        )
        self._thread.start()
        if not self._ready_event.wait(timeout=3.0):
            raise RuntimeError("Mock mobile USB runtime failed to start.")

    def stop(self) -> None:
        self._shutdown_event.set()
        if self._server is not None:
            self._server.shutdown()
        if self._thread is not None:
            self._thread.join(timeout=2.0)

    def _run_server(self) -> None:
        with serve(self._handle_connection, "127.0.0.1", self._port) as server:
            self._server = server
            self._ready_event.set()
            server.serve_forever()

    def _handle_connection(self, websocket: ServerConnection) -> None:
        while not self._shutdown_event.is_set():
            try:
                raw_message = websocket.recv(timeout=0.2)
            except TimeoutError:
                continue
            except ConnectionClosed:
                return

            envelope = json.loads(raw_message)
            if envelope.get("operation") != USB_AUTH_CHALLENGE_OPERATION:
                continue
            request_id = envelope.get("request_id")
            body = envelope.get("body")
            if not isinstance(request_id, str) or not isinstance(body, dict):
                return
            sid = body.get("sid")
            rand = body.get("rand")
            if sid != self._session_id or not isinstance(rand, str) or not rand:
                return

            proof = hashlib.sha256(f"{self._one_time_passcode}{rand}".encode("utf-8")).hexdigest()
            response_envelope = {
                "schema": "dtis.mobile-transport.v1",
                "request_id": request_id,
                "status_code": 200,
                "body": {
                    "schema": "dtis.mobile-transport.v1",
                    "status": "accepted",
                    "proof": proof,
                },
            }
            websocket.send(json.dumps(response_envelope, separators=(",", ":"), sort_keys=True))
            self.challenge_received.set()

    @staticmethod
    def _find_free_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return sock.getsockname()[1]


class TestUsbHandshakePcSideFunctional(unittest.TestCase):
    def test_pc_usb_handshake_uses_probe_and_verifies_mobile_challenge(self):
        session_id = "functional-usb-session-001"
        one_time_passcode = "482913"
        device_udid = "functional-ios-001"

        mobile_runtime = _MockMobileUsbRuntimeServer(
            session_id=session_id,
            one_time_passcode=one_time_passcode,
        )
        mobile_runtime.start()
        self.addCleanup(mobile_runtime.stop)

        tunnel_provider = _LoopbackUsbTunnelProvider(
            device_udid=device_udid,
            connect_port=mobile_runtime.port,
        )
        adapter = UsbWebSocketTransportAdapter(
            router=MobileTransportRouter(),
            log_handler=self._noop_log,
            tunnel_provider=tunnel_provider,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id=session_id,
                one_time_passcode=one_time_passcode,
                suggested_port=mobile_runtime.port,
                fallback_port_window=0,
            )
        )
        adapter.start()
        self.addCleanup(adapter.stop)

        self.assertTrue(
            self._wait_until(
                lambda: adapter.state == UsbTransportState.CONNECTED,
                timeout_seconds=2.0,
            )
        )
        self.assertTrue(mobile_runtime.challenge_received.is_set())
        self.assertEqual(
            tunnel_provider.probe_calls,
            [(device_udid, mobile_runtime.port)],
        )
        self.assertEqual(
            tunnel_provider.connect_calls,
            [(device_udid, mobile_runtime.port)],
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
