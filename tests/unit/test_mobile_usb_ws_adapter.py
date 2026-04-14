import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.contracts import (
    MobileTransportKind,
    MobileTransportResponse,
)
from dt_image_search.mobile.transport.router import MobileTransportRouter
from dt_image_search.mobile.transport.usb_ws_adapter import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    UsbBootstrapConfig,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
)


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

    @staticmethod
    def _noop_log(*args, **kwargs):
        return None


if __name__ == "__main__":
    unittest.main()
