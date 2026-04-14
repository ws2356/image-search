import os
import socket
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.usb_tunnel import (
    Pymobiledevice3UsbTunnelProvider,
    UsbTunnelConnectError,
    UsbTunnelDeviceNotFoundError,
    UsbTunnelUnavailableError,
)


class _FakeConnectionFailedError(RuntimeError):
    pass


class _FakeMuxException(RuntimeError):
    pass


class _FakeExceptionsModule:
    ConnectionFailedError = _FakeConnectionFailedError
    MuxException = _FakeMuxException
    ConnectionFailedToUsbmuxdError = _FakeConnectionFailedError
    BadDevError = _FakeConnectionFailedError


class _FakeMuxDevice:
    def __init__(
        self,
        *,
        serial: str,
        connection_type: str = "USB",
        connectable_ports: set[int] | None = None,
    ):
        self.serial = serial
        self.connection_type = connection_type
        self._connectable_ports = connectable_ports or set()

    async def connect(self, port: int):
        if port not in self._connectable_ports:
            raise _FakeConnectionFailedError(f"Port {port} is closed")
        client_socket, server_socket = socket.socketpair()
        server_socket.close()
        return client_socket


class _FakeUsbmuxModule:
    def __init__(self, devices: tuple[_FakeMuxDevice, ...]):
        self._devices = devices
        self.last_connection_type = None
        self.last_select_udid = None
        self.last_select_connection_type = None

    async def select_devices_by_connection_type(self, connection_type: str):
        self.last_connection_type = connection_type
        return [device for device in self._devices if device.connection_type == connection_type]

    async def select_device(self, udid: str, connection_type: str | None = None):
        self.last_select_udid = udid
        self.last_select_connection_type = connection_type
        for device in self._devices:
            if connection_type is not None and device.connection_type != connection_type:
                continue
            if device.serial.replace("-", "") == udid.replace("-", ""):
                return device
        return None


class TestPymobiledevice3UsbTunnelProvider(unittest.TestCase):
    def test_list_usb_devices_returns_serialized_devices(self):
        usbmux_module = _FakeUsbmuxModule(
            devices=(
                _FakeMuxDevice(serial="ios-usb-001", connection_type="USB"),
                _FakeMuxDevice(serial="ios-net-001", connection_type="Network"),
            )
        )
        provider = Pymobiledevice3UsbTunnelProvider(
            usbmux_module=usbmux_module,
            exceptions_module=_FakeExceptionsModule(),
        )

        devices = provider.list_usb_devices()

        self.assertEqual(usbmux_module.last_connection_type, "USB")
        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0].udid, "ios-usb-001")
        self.assertEqual(devices[0].connection_type, "USB")

    def test_probe_device_port_returns_true_when_connection_succeeds(self):
        usbmux_module = _FakeUsbmuxModule(
            devices=(
                _FakeMuxDevice(
                    serial="ios-usb-001",
                    connection_type="USB",
                    connectable_ports={50211},
                ),
            )
        )
        provider = Pymobiledevice3UsbTunnelProvider(
            usbmux_module=usbmux_module,
            exceptions_module=_FakeExceptionsModule(),
        )

        can_connect = provider.probe_device_port(udid="ios-usb-001", port=50211)

        self.assertTrue(can_connect)
        self.assertEqual(usbmux_module.last_select_udid, "ios-usb-001")
        self.assertEqual(usbmux_module.last_select_connection_type, "USB")

    def test_probe_device_port_returns_false_when_connection_fails(self):
        usbmux_module = _FakeUsbmuxModule(
            devices=(
                _FakeMuxDevice(
                    serial="ios-usb-001",
                    connection_type="USB",
                    connectable_ports=set(),
                ),
            )
        )
        provider = Pymobiledevice3UsbTunnelProvider(
            usbmux_module=usbmux_module,
            exceptions_module=_FakeExceptionsModule(),
        )

        can_connect = provider.probe_device_port(udid="ios-usb-001", port=50211)

        self.assertFalse(can_connect)

    def test_connect_device_port_raises_when_device_is_missing(self):
        usbmux_module = _FakeUsbmuxModule(devices=tuple())
        provider = Pymobiledevice3UsbTunnelProvider(
            usbmux_module=usbmux_module,
            exceptions_module=_FakeExceptionsModule(),
        )

        with self.assertRaises(UsbTunnelDeviceNotFoundError):
            provider.connect_device_port(udid="ios-usb-001", port=50211)

    def test_connect_device_port_raises_when_connection_fails(self):
        usbmux_module = _FakeUsbmuxModule(
            devices=(
                _FakeMuxDevice(
                    serial="ios-usb-001",
                    connection_type="USB",
                ),
            )
        )
        provider = Pymobiledevice3UsbTunnelProvider(
            usbmux_module=usbmux_module,
            exceptions_module=_FakeExceptionsModule(),
        )

        with self.assertRaises(UsbTunnelConnectError):
            provider.connect_device_port(udid="ios-usb-001", port=50211)

    def test_missing_pymobiledevice3_raises_unavailable_error(self):
        with patch(
            "dt_image_search.mobile.transport.usb_tunnel.importlib.import_module",
            side_effect=ImportError("No module named pymobiledevice3"),
        ):
            provider = Pymobiledevice3UsbTunnelProvider()

            with self.assertRaises(UsbTunnelUnavailableError):
                provider.list_usb_devices()


if __name__ == "__main__":
    unittest.main()
