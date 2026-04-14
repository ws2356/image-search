import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.lan_http_adapter import LanHttpEndpointInfo
from dt_image_search.mobile.transport.transport_manager import MobileTransportManager
from dt_image_search.mobile.transport.usb_ws_adapter import (
    UsbBootstrapConfig,
    UsbTransportState,
)


class _FakeLanTransport:
    def __init__(self):
        self.start_called = 0
        self.stop_called = 0
        self.endpoint_info = LanHttpEndpointInfo(
            endpoint_url="http://127.0.0.1:50123/api/mobile/pairing/claim",
            endpoint_urls=("http://127.0.0.1:50123/api/mobile/pairing/claim",),
        )

    def start(self) -> LanHttpEndpointInfo:
        self.start_called += 1
        return self.endpoint_info

    def stop(self) -> None:
        self.stop_called += 1


class _FakeUsbTransport:
    def __init__(self):
        self.configure_called = 0
        self.start_called = 0
        self.stop_called = 0
        self.bootstrap_config = None
        self.state = UsbTransportState.STOPPED
        self.active_tunnel_target = None
        self.last_probe_error = None

    def configure_bootstrap(self, config: UsbBootstrapConfig) -> None:
        self.configure_called += 1
        self.bootstrap_config = config
        self.state = UsbTransportState.CONFIGURED

    def start(self) -> None:
        self.start_called += 1
        self.state = UsbTransportState.READY

    def stop(self) -> None:
        self.stop_called += 1
        self.state = UsbTransportState.STOPPED


class TestMobileTransportManager(unittest.TestCase):
    def test_start_lan_delegates_to_lan_transport(self):
        fake_lan = _FakeLanTransport()
        fake_usb = _FakeUsbTransport()
        manager = MobileTransportManager(lan_transport=fake_lan, usb_transport=fake_usb)

        endpoint_info = manager.start_lan()

        self.assertEqual(fake_lan.start_called, 1)
        self.assertEqual(
            endpoint_info.endpoint_url,
            "http://127.0.0.1:50123/api/mobile/pairing/claim",
        )

    def test_usb_lifecycle_helpers_delegate_to_usb_transport(self):
        fake_lan = _FakeLanTransport()
        fake_usb = _FakeUsbTransport()
        manager = MobileTransportManager(lan_transport=fake_lan, usb_transport=fake_usb)
        config = UsbBootstrapConfig(
            session_id="session-001",
            one_time_passcode="482913",
            suggested_port=50123,
            fallback_port_window=20,
        )

        manager.configure_usb_bootstrap(config)
        state_after_start = manager.start_usb()
        manager.stop_usb()

        self.assertEqual(fake_usb.configure_called, 1)
        self.assertEqual(fake_usb.start_called, 1)
        self.assertEqual(fake_usb.stop_called, 1)
        self.assertEqual(state_after_start, UsbTransportState.READY)
        self.assertEqual(manager.usb_bootstrap_config, config)
        self.assertEqual(manager.usb_state, UsbTransportState.STOPPED)
        self.assertIsNone(manager.usb_active_tunnel_target)
        self.assertIsNone(manager.usb_last_probe_error)

    def test_stop_all_stops_both_transports(self):
        fake_lan = _FakeLanTransport()
        fake_usb = _FakeUsbTransport()
        manager = MobileTransportManager(lan_transport=fake_lan, usb_transport=fake_usb)

        manager.stop_all()

        self.assertEqual(fake_lan.stop_called, 1)
        self.assertEqual(fake_usb.stop_called, 1)


if __name__ == "__main__":
    unittest.main()
