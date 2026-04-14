import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.contracts import (
    MobileTransportKind,
    MobileTransportResponse,
)
from dt_image_search.mobile.transport.router import MobileTransportRouter
from dt_image_search.mobile.transport.usb_tunnel import (
    UsbConnectedDevice,
    UsbTunnelUnavailableError,
)
from dt_image_search.mobile.transport.usb_ws_adapter import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    UsbBootstrapConfig,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
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


class TestUsbWebSocketTransportAdapter(unittest.TestCase):
    def setUp(self):
        self._router = MobileTransportRouter()
        self._adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
        )

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
            '{"schema":"dtis.mobile-transport.v1","operation":"transfer.unknown","body":{}}'
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.payload["schema"], MOBILE_TRANSPORT_ENVELOPE_SCHEMA)
        self.assertEqual(response.payload["status"], "rejected")
        self.assertIn("does not support", response.payload["message"])

    def test_state_transitions(self):
        self._adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="session-001",
                one_time_passcode="482913",
                suggested_port=50211,
                fallback_port_window=20,
            )
        )
        self.assertEqual(self._adapter.state, UsbTransportState.CONFIGURED)
        self._adapter.start()
        self.assertEqual(self._adapter.state, UsbTransportState.READY)
        self._adapter.mark_connected()
        self.assertEqual(self._adapter.state, UsbTransportState.CONNECTED)
        self._adapter.stop()
        self.assertEqual(self._adapter.state, UsbTransportState.STOPPED)

    def test_start_marks_connected_when_usb_probe_succeeds(self):
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
            connectable_ports={("ios-001", 50213)},
        )
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
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

        self.assertEqual(adapter.state, UsbTransportState.CONNECTED)
        self.assertIsNotNone(adapter.active_tunnel_target)
        self.assertEqual(adapter.active_tunnel_target.device_udid, "ios-001")
        self.assertEqual(adapter.active_tunnel_target.remote_port, 50213)
        self.assertEqual(
            provider.probe_calls,
            [
                ("ios-001", 50211),
                ("ios-001", 50212),
                ("ios-001", 50210),
                ("ios-001", 50213),
            ],
        )

    def test_start_records_probe_error_when_no_port_is_reachable(self):
        provider = _FakeUsbTunnelProvider(
            devices=(UsbConnectedDevice(udid="ios-001"),),
        )
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
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

        self.assertEqual(adapter.state, UsbTransportState.READY)
        self.assertIsNone(adapter.active_tunnel_target)
        self.assertEqual(
            adapter.last_probe_error,
            "Desktop could not connect to any USB bootstrap port candidates.",
        )

    def test_start_records_probe_error_when_provider_is_unavailable(self):
        provider = _FakeUsbTunnelProvider(unavailable_error="pymobiledevice3 not installed")
        adapter = UsbWebSocketTransportAdapter(
            router=self._router,
            log_handler=self._noop_log,
            tunnel_provider=provider,
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

        self.assertEqual(adapter.state, UsbTransportState.READY)
        self.assertEqual(adapter.last_probe_error, "pymobiledevice3 not installed")

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


if __name__ == "__main__":
    unittest.main()
