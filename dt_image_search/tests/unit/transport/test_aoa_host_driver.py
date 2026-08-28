#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the AOA host driver (simulated + PyUSB logic).

Author: deepseek-v4-flash-free
Date: 2026-08-01
"""

from __future__ import annotations

import errno
import time
import unittest
from unittest import mock

import usb.core as usb_core
import usb.util as usb_util

from dt_image_search.mobile.transport.aoa_frame_codec import encode_aoa_frame
from dt_image_search.mobile.transport.aoa_host_driver import (
    AOA_ACCESSORY_PRODUCT_IDS,
    AOA_GET_PROTOCOL_REQUEST,
    AOA_SEND_STRING_REQUEST,
    AOA_START_ACCESSORY_REQUEST,
    AOA_VENDOR_REQUEST_IN,
    AOA_VENDOR_REQUEST_OUT,
    GOOGLE_VENDOR_ID,
    AoaDetectedDevice,
    AoaHostState,
    PyUsbAoaHostDriver,
    SimulatedAoaHostDriver,
)

REQUEST_ID = "12345678-1234-1234-1234-123456789012"

_ACCESSORY_DEVICE = AoaDetectedDevice(
    device_id="sim-device",
    vendor_id=GOOGLE_VENDOR_ID,
    product_id=0x2D01,
    serial_number="serial-001",
    bus=1,
    address=2,
    is_accessory_mode=True,
)

_NEGOTIATION_DEVICE = AoaDetectedDevice(
    device_id="sim-device",
    vendor_id=GOOGLE_VENDOR_ID,
    product_id=0x2D01,
    serial_number="serial-001",
    bus=1,
    address=2,
    is_accessory_mode=False,
)


class TestSimulatedAoaHostDriver(unittest.TestCase):
    def test_start_without_devices_goes_scanning(self) -> None:
        driver = SimulatedAoaHostDriver()
        driver.start()
        self.assertEqual(driver.state, AoaHostState.SCANNING)

    def test_start_with_devices_goes_connected(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        driver.start()
        self.assertEqual(driver.state, AoaHostState.CONNECTED)

    def test_stop_resets_state_and_last_error(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        driver.start()
        driver._last_error = "boom"  # noqa: SLF001
        driver.stop()
        self.assertEqual(driver.state, AoaHostState.STOPPED)
        self.assertIsNone(driver.last_error)

    def test_detect_devices_returns_configured_devices(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        self.assertEqual(driver.detect_devices(), [_ACCESSORY_DEVICE])

    def test_ensure_accessory_mode_short_circuits(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        self.assertTrue(driver.ensure_accessory_mode(_NEGOTIATION_DEVICE))
        self.assertEqual(driver.state, AoaHostState.ACCESSORY_MODE)

    def test_open_stream_goes_connected(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        driver.start()
        read_stream, write_stream = driver.open_stream(_ACCESSORY_DEVICE)
        self.assertEqual(driver.state, AoaHostState.CONNECTED)
        read_stream.close()
        write_stream.close()

    def test_inject_and_read_frame_round_trip(self) -> None:
        driver = SimulatedAoaHostDriver(devices=[_ACCESSORY_DEVICE])
        driver.start()
        read_stream, write_stream = driver.open_stream(_ACCESSORY_DEVICE)
        frame = encode_aoa_frame(REQUEST_ID, b"ping")
        driver.inject_frame(frame)
        self.assertEqual(read_stream.read(-1, timeout=0.5), frame)
        self.assertEqual(write_stream.write(frame), len(frame))
        self.assertEqual(driver.read_frame(timeout=0.5), frame)
        read_stream.close()
        write_stream.close()

    def test_read_frame_timeout_returns_none(self) -> None:
        driver = SimulatedAoaHostDriver()
        self.assertIsNone(driver.read_frame(timeout=0.05))

    def test_stream_read_returns_partial_sizes(self) -> None:
        driver = SimulatedAoaHostDriver()
        read_stream, write_stream = driver.open_stream(_ACCESSORY_DEVICE)
        driver.inject_frame(b"abcdef")
        self.assertEqual(read_stream.read(2, timeout=0.5), b"ab")
        self.assertEqual(read_stream.read(2, timeout=0.5), b"cd")
        self.assertEqual(read_stream.read(2, timeout=0.5), b"ef")
        read_stream.close()
        write_stream.close()

    def test_stream_read_timeout_raises(self) -> None:
        driver = SimulatedAoaHostDriver()
        read_stream, _ = driver.open_stream(_ACCESSORY_DEVICE)
        with self.assertRaises(TimeoutError):
            read_stream.read(-1, timeout=0.05)
        read_stream.close()

    def test_write_after_close_raises(self) -> None:
        driver = SimulatedAoaHostDriver()
        read_stream, write_stream = driver.open_stream(_ACCESSORY_DEVICE)
        read_stream.close()
        write_stream.close()
        with self.assertRaises(RuntimeError):
            write_stream.write(b"late")


class _FakeEndpoint:
    def __init__(self, address: int) -> None:
        self.bEndpointAddress = address
        self.wMaxPacketSize = 512


class _FakeInterface:
    def __init__(self, endpoints: list[_FakeEndpoint]) -> None:
        self.bInterfaceNumber = 0
        self._endpoints = endpoints

    def __iter__(self):
        return iter(self._endpoints)


class _FakeConfiguration:
    def __init__(self, endpoints: list[_FakeEndpoint]) -> None:
        self._interface = _FakeInterface(endpoints)

    def __getitem__(self, key: tuple[int, int]):
        return self._interface


class _FakeRawDevice:
    """Stand-in for a pyusb Device with the AOA protocol vendor requests."""

    def __init__(
        self,
        *,
        vid: int = 0x1234,
        pid: int = 0x5678,
        bus: int = 1,
        address: int = 2,
        serial_number: str | None = "serial-001",
        protocol_supported: bool = True,
        accessory_mode: bool = False,
    ) -> None:
        self.idVendor = vid
        self.idProduct = pid
        self.bus = bus
        self.address = address
        self.serial_number = serial_number
        self._protocol_supported = protocol_supported
        self._accessory_mode = accessory_mode

    def ctrl_transfer(self, bm_request_type, b_request, w_value, w_index, data_or_w_length, timeout=0):  # noqa: ANN001
        if b_request == AOA_GET_PROTOCOL_REQUEST:
            return b"\x02\x00" if self._protocol_supported else b""
        return b""

    def get_active_configuration(self) -> _FakeConfiguration:
        return _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )

    def set_configuration(self) -> None:
        return None

    def read(self, endpoint_address: int, size: int, timeout: int = 0) -> bytes:  # noqa: ARG001
        return b"from-device"

    def write(self, endpoint_address: int, data: bytes, timeout: int = 0) -> int:  # noqa: ARG001
        return len(data)


class TestPyUsbAoaHostDriverDetection(unittest.TestCase):
    def _driver(self) -> PyUsbAoaHostDriver:
        return PyUsbAoaHostDriver()

    def test_detect_devices_skips_unsupported_devices(self) -> None:
        driver = self._driver()
        unsupported = _FakeRawDevice(protocol_supported=False)
        supported = _FakeRawDevice(vid=0x1234, pid=0x5678, protocol_supported=True)
        with mock.patch.object(usb_core, "find", return_value=[unsupported, supported]):
            detected = driver.detect_devices()
        self.assertEqual(len(detected), 1)
        self.assertEqual(detected[0].device_id, "serial-001")

    def test_detect_devices_flags_accessory_mode(self) -> None:
        driver = self._driver()
        accessory = _FakeRawDevice(
            vid=GOOGLE_VENDOR_ID,
            pid=sorted(AOA_ACCESSORY_PRODUCT_IDS)[0],
            protocol_supported=False,
        )
        with mock.patch.object(usb_core, "find", return_value=[accessory]):
            detected = driver.detect_devices()
        self.assertEqual(len(detected), 1)
        self.assertTrue(detected[0].is_accessory_mode)

    def test_detect_devices_falls_back_to_bus_address_id(self) -> None:
        driver = self._driver()
        no_serial = _FakeRawDevice(serial_number=None, bus=7, address=9)
        with mock.patch.object(usb_core, "find", return_value=[no_serial]):
            detected = driver.detect_devices()
        self.assertEqual(detected[0].device_id, "usb-7-9")

    def test_detect_devices_returns_empty_for_no_devices(self) -> None:
        driver = self._driver()
        with mock.patch.object(usb_core, "find", return_value=[]):
            self.assertEqual(driver.detect_devices(), [])

    def test_start_and_stop(self) -> None:
        driver = self._driver()
        driver.start()
        self.assertEqual(driver.state, AoaHostState.SCANNING)
        driver.stop()
        self.assertEqual(driver.state, AoaHostState.STOPPED)


class TestPyUsbAoaHostDriverNegotiation(unittest.TestCase):
    def test_ensure_accessory_mode_short_circuits_for_accessory(self) -> None:
        driver = PyUsbAoaHostDriver()
        self.assertTrue(driver.ensure_accessory_mode(_ACCESSORY_DEVICE))

    def test_ensure_accessory_mode_performs_negotiation(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.ctrl_transfer.return_value = b"\x02\x00"
        handle.serial_number = "serial-001"

        accessory_raw = _FakeRawDevice(
            vid=GOOGLE_VENDOR_ID,
            pid=0x2D00,
            protocol_supported=False,
        )

        def fake_find(*, find_all: bool = False, **kwargs):
            if find_all:
                return [accessory_raw]
            return handle

        with mock.patch.object(usb_core, "find", side_effect=fake_find), mock.patch.object(
            usb_util, "dispose_resources"
        ) as dispose:
            self.assertTrue(driver.ensure_accessory_mode(_NEGOTIATION_DEVICE))

        protocol_calls = [
            call
            for call in handle.ctrl_transfer.call_args_list
            if call[0][1] == AOA_GET_PROTOCOL_REQUEST
        ]
        string_calls = [
            call
            for call in handle.ctrl_transfer.call_args_list
            if call[0][1] == AOA_SEND_STRING_REQUEST
        ]
        start_calls = [
            call
            for call in handle.ctrl_transfer.call_args_list
            if call[0][1] == AOA_START_ACCESSORY_REQUEST
        ]
        self.assertEqual(len(protocol_calls), 1)
        self.assertEqual(len(string_calls), 6)
        self.assertEqual(len(start_calls), 1)
        dispose.assert_called_once_with(handle)

    def test_ensure_accessory_mode_raises_when_protocol_unavailable(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.ctrl_transfer.return_value = b""
        with mock.patch.object(usb_core, "find", return_value=handle):
            with self.assertRaises(RuntimeError):
                driver.ensure_accessory_mode(_NEGOTIATION_DEVICE)

    def test_ensure_accessory_mode_raises_when_handle_not_found(self) -> None:
        driver = PyUsbAoaHostDriver()
        with mock.patch.object(usb_core, "find", return_value=None):
            with self.assertRaises(RuntimeError):
                driver.ensure_accessory_mode(_NEGOTIATION_DEVICE)

    def test_ensure_accessory_mode_raises_on_usb_error(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.ctrl_transfer.side_effect = usb_core.USBError("boom")
        with mock.patch.object(usb_core, "find", return_value=handle):
            with self.assertRaises(RuntimeError):
                driver.ensure_accessory_mode(_NEGOTIATION_DEVICE)


class TestPyUsbAoaHostDriverStreams(unittest.TestCase):
    def test_open_stream_returns_working_streams(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        handle.read.return_value = b"from-device"
        handle.write.return_value = 4

        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"):
            read_stream, write_stream = driver.open_stream(_ACCESSORY_DEVICE)

        self.assertEqual(driver.state, AoaHostState.CONNECTED)
        self.assertEqual(read_stream.read(), b"from-device")
        self.assertEqual(write_stream.write(b"data"), 4)

    def test_open_stream_raises_when_endpoints_missing(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01)]
        )
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", return_value=None
        ), mock.patch.object(usb_util, "claim_interface"):
            with self.assertRaises(RuntimeError):
                driver.open_stream(_ACCESSORY_DEVICE)

    def test_open_stream_raises_when_handle_not_found(self) -> None:
        driver = PyUsbAoaHostDriver()
        with mock.patch.object(usb_core, "find", return_value=None):
            with self.assertRaises(RuntimeError):
                driver.open_stream(_ACCESSORY_DEVICE)

    def test_open_stream_reads_active_configuration_without_setting(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"):
            driver.open_stream(_ACCESSORY_DEVICE)
        handle.set_configuration.assert_not_called()

    def test_open_stream_sets_configuration_when_active_configuration_missing(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.side_effect = [
            usb_core.USBError("configuration not set"),
            _FakeConfiguration([_FakeEndpoint(0x01), _FakeEndpoint(0x81)]),
        ]
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"):
            driver.open_stream(_ACCESSORY_DEVICE)
        handle.set_configuration.assert_called_once()

    def test_open_stream_releases_previous_handle_before_reopen(self) -> None:
        driver = PyUsbAoaHostDriver()
        first_handle = mock.Mock()
        first_handle.serial_number = "serial-001"
        first_handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        second_handle = mock.Mock()
        second_handle.serial_number = "serial-001"
        second_handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        handles = iter([first_handle, second_handle])
        with mock.patch.object(
            usb_core, "find", side_effect=lambda **kwargs: next(handles)
        ), mock.patch.object(
            usb_util,
            "find_descriptor",
            side_effect=[
                _FakeEndpoint(0x01),
                _FakeEndpoint(0x81),
                _FakeEndpoint(0x01),
                _FakeEndpoint(0x81),
            ],
        ), mock.patch.object(usb_util, "claim_interface"), mock.patch.object(
            usb_util, "release_interface"
        ) as release, mock.patch.object(
            usb_util, "dispose_resources"
        ) as dispose:
            driver.open_stream(_ACCESSORY_DEVICE)
            driver.open_stream(_ACCESSORY_DEVICE)

        release.assert_called_once_with(first_handle, 0)
        dispose.assert_called_once_with(first_handle)

    def test_stop_releases_active_handle(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"), mock.patch.object(
            usb_util, "release_interface"
        ) as release, mock.patch.object(usb_util, "dispose_resources") as dispose:
            driver.open_stream(_ACCESSORY_DEVICE)
            driver.stop()
        release.assert_called_once()
        dispose.assert_called_once()
        self.assertEqual(driver.state, AoaHostState.STOPPED)

    def test_read_stream_translates_usb_timeout_to_timeout_error(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        handle.read.side_effect = usb_core.USBError(
            "Operation timed out", error_code=-7, errno=errno.ETIMEDOUT
        )
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"):
            read_stream, _ = driver.open_stream(_ACCESSORY_DEVICE)
        with self.assertRaises(TimeoutError):
            read_stream.read(timeout=0.5)

    def test_read_stream_wraps_non_timeout_usb_error(self) -> None:
        driver = PyUsbAoaHostDriver()
        handle = mock.Mock()
        handle.serial_number = "serial-001"
        handle.get_active_configuration.return_value = _FakeConfiguration(
            [_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        )
        handle.read.side_effect = usb_core.USBError(
            "No such device", error_code=-4, errno=errno.ENODEV
        )
        with mock.patch.object(usb_core, "find", return_value=handle), mock.patch.object(
            usb_util, "find_descriptor", side_effect=[_FakeEndpoint(0x01), _FakeEndpoint(0x81)]
        ), mock.patch.object(usb_util, "claim_interface"):
            read_stream, _ = driver.open_stream(_ACCESSORY_DEVICE)
        with self.assertRaises(RuntimeError):
            read_stream.read(timeout=0.5)


if __name__ == "__main__":
    unittest.main()
