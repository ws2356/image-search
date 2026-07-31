#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Host-side driver for Android Open Accessory (AOA) USB transport.

Provides an abstract interface, a PyUSB implementation for real devices, and an
in-memory simulated implementation for unit tests.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import queue
import threading
import time
from typing import Any, Protocol

import usb.core as _usb_core
import usb.util as _usb_util

AOA_GET_PROTOCOL_REQUEST = 51
AOA_SEND_STRING_REQUEST = 52
AOA_START_ACCESSORY_REQUEST = 53
AOA_VENDOR_REQUEST_IN = 0xC0
AOA_VENDOR_REQUEST_OUT = 0x40
GOOGLE_VENDOR_ID = 0x18D1
AOA_ACCESSORY_PRODUCT_IDS = frozenset(
    {
        0x2D00,  # accessory
        0x2D01,  # accessory + adb
        0x2D02,  # audio
        0x2D03,  # audio + adb
        0x2D04,  # accessory + audio
        0x2D05,  # accessory + audio + adb
    }
)


class AoaHostState(str, Enum):
    STOPPED = "stopped"
    SCANNING = "scanning"
    ACCESSORY_MODE = "accessory_mode"
    CONNECTED = "connected"
    ERROR = "error"


@dataclass(frozen=True)
class AoaDetectedDevice:
    """A USB device that either is in AOA accessory mode or supports AOA negotiation."""

    device_id: str
    vendor_id: int
    product_id: int
    serial_number: str | None
    bus: int | None = None
    address: int | None = None
    is_accessory_mode: bool = False


class AoaReadStream(Protocol):
    """Readable stream returned by the AOA host driver."""

    def read(self, size: int = -1, timeout: float | None = None) -> bytes: ...

    def close(self) -> None: ...


class AoaWriteStream(Protocol):
    """Writable stream returned by the AOA host driver."""

    def write(self, data: bytes) -> int: ...

    def close(self) -> None: ...


class AoaHostDriver(Protocol):
    """Platform-agnostic interface for AOA host operations."""

    def start(self) -> None: ...

    def stop(self) -> None: ...

    @property
    def state(self) -> AoaHostState: ...

    @property
    def last_error(self) -> str | None: ...

    def detect_devices(self) -> list[AoaDetectedDevice]: ...

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool: ...

    def open_stream(
        self,
        device: AoaDetectedDevice,
    ) -> tuple[AoaReadStream, AoaWriteStream]: ...


class _SimulatedAoaStream:
    """Thread-safe byte queue exposed as a readable/writable stream."""

    def __init__(self, queue: queue.Queue[bytes | None]) -> None:
        self._queue = queue
        self._buffer = bytearray()
        self._closed = False

    def read(self, size: int = -1, timeout: float | None = None) -> bytes:
        if self._closed:
            return b""
        if size == 0:
            return b""
        deadline = None if timeout is None else time.monotonic() + timeout
        while size < 0 or len(self._buffer) < size:
            remaining = None
            if deadline is not None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
            try:
                chunk = self._queue.get(timeout=remaining)
            except queue.Empty:
                if deadline is not None:
                    break
                continue
            if chunk is None:
                self._closed = True
                break
            self._buffer.extend(chunk)

        if len(self._buffer) == 0 and deadline is not None and time.monotonic() >= deadline:
            raise TimeoutError("Simulated AOA stream read timed out.")

        if size < 0:
            result = bytes(self._buffer)
            self._buffer.clear()
        else:
            result = bytes(self._buffer[:size])
            del self._buffer[:size]
        return result

    def write(self, data: bytes) -> int:
        if self._closed:
            raise RuntimeError("Cannot write to a closed simulated AOA stream.")
        self._queue.put(bytes(data))
        return len(data)

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            self._queue.put(None)


class SimulatedAoaHostDriver:
    """In-memory AOA driver for unit tests."""

    def __init__(
        self,
        devices: list[AoaDetectedDevice] | None = None,
    ) -> None:
        self._devices = list(devices) if devices is not None else []
        self._state = AoaHostState.STOPPED
        self._last_error: str | None = None
        self._input_queue: queue.Queue[bytes | None] = queue.Queue()
        self._output_queue: queue.Queue[bytes | None] = queue.Queue()
        self._host_read: _SimulatedAoaStream | None = None
        self._host_write: _SimulatedAoaStream | None = None

    def start(self) -> None:
        self._state = AoaHostState.SCANNING
        if self._devices:
            self._state = AoaHostState.CONNECTED

    def stop(self) -> None:
        self._state = AoaHostState.STOPPED
        self._last_error = None
        if self._host_read is not None:
            self._host_read.close()
        if self._host_write is not None:
            self._host_write.close()

    @property
    def state(self) -> AoaHostState:
        return self._state

    @property
    def last_error(self) -> str | None:
        return self._last_error

    def detect_devices(self) -> list[AoaDetectedDevice]:
        return list(self._devices)

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        self._state = AoaHostState.ACCESSORY_MODE
        return True

    def open_stream(
        self,
        device: AoaDetectedDevice,
    ) -> tuple[AoaReadStream, AoaWriteStream]:
        self._host_read = _SimulatedAoaStream(self._input_queue)
        self._host_write = _SimulatedAoaStream(self._output_queue)
        self._state = AoaHostState.CONNECTED
        return self._host_read, self._host_write

    def inject_frame(self, frame: bytes, timeout: float = 10.0) -> None:
        """Inject a mobile->host frame into the stream read by the adapter."""
        self._input_queue.put(frame, timeout=timeout)

    def read_frame(self, timeout: float = 1.0) -> bytes | None:
        """Read the next host->mobile frame produced by the adapter."""
        try:
            item = self._output_queue.get(timeout=timeout)
        except queue.Empty:
            return None
        return item


class PyUsbAoaHostDriver:
    """PyUSB-based AOA host driver for macOS/Windows production use."""

    def __init__(self) -> None:
        self._usb_core = _usb_core
        self._usb_util = _usb_util
        self._usb_error_type: type[BaseException] = RuntimeError
        if self._usb_core is not None:
            usb_error = getattr(self._usb_core, "USBError", None)
            if isinstance(usb_error, type) and issubclass(usb_error, BaseException):
                self._usb_error_type = usb_error
        self._state = AoaHostState.STOPPED
        self._last_error: str | None = None
        self._active_device: AoaDetectedDevice | None = None
        self._active_handle: Any | None = None

    def start(self) -> None:
        self._state = AoaHostState.SCANNING

    def stop(self) -> None:
        self._release_active_handle()
        self._state = AoaHostState.STOPPED

    @property
    def state(self) -> AoaHostState:
        return self._state

    @property
    def last_error(self) -> str | None:
        return self._last_error

    def detect_devices(self) -> list[AoaDetectedDevice]:
        self._require_pyusb()
        usb_core = self._usb_core
        if usb_core is None:
            raise RuntimeError(
                "AOA host driver were not initialized with a USB core module."
            )
        raw_devices = list(usb_core.find(find_all=True) or [])
        detected: list[AoaDetectedDevice] = []
        for raw_device in raw_devices:
            id_vendor = int(getattr(raw_device, "idVendor", 0) or 0)
            id_product = int(getattr(raw_device, "idProduct", 0) or 0)
            is_accessory = (
                id_vendor == GOOGLE_VENDOR_ID and id_product in AOA_ACCESSORY_PRODUCT_IDS
            )
            supports_aoa = is_accessory or self._supports_aoa_protocol(raw_device)
            if not supports_aoa:
                continue
            serial = self._serial_number(raw_device)
            device_id = self._device_id(raw_device, serial)
            detected.append(
                AoaDetectedDevice(
                    device_id=device_id,
                    vendor_id=id_vendor,
                    product_id=id_product,
                    serial_number=serial,
                    bus=getattr(raw_device, "bus", None),
                    address=getattr(raw_device, "address", None),
                    is_accessory_mode=is_accessory,
                )
            )
        return detected

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        if device.is_accessory_mode:
            return True
        self._require_pyusb()
        usb_util = self._usb_util
        if usb_util is None:
            raise RuntimeError("AOA host driver were not initialized with a USB utility module.")

        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA host could not find the selected USB device handle.")

        try:
            protocol_response = device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_IN,
                AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=1500,
            )
            protocol_version = 0
            if len(protocol_response) == 2:
                protocol_version = int(protocol_response[0]) | (int(protocol_response[1]) << 8)
            if protocol_version <= 0:
                raise RuntimeError("AOA protocol version is unavailable on detected device.")
            strings = (
                "AuSearch",
                "AuBackup AOA",
                "Android AOA backup transport",
                "1.0",
                "https://www.boldman.net",
                "aubackup-aoa",
            )
            for string_index, string_value in enumerate(strings):
                device_handle.ctrl_transfer(
                    AOA_VENDOR_REQUEST_OUT,
                    AOA_SEND_STRING_REQUEST,
                    0,
                    string_index,
                    string_value.encode("utf-8"),
                    timeout=1500,
                )
            device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_OUT,
                AOA_START_ACCESSORY_REQUEST,
                0,
                0,
                b"",
                timeout=1500,
            )
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA negotiation failed: {exc}") from exc
        finally:
            usb_util.dispose_resources(device_handle)

        accessory_deadline = time.monotonic() + 8.0
        while time.monotonic() < accessory_deadline:
            for detected_device in self.detect_devices():
                if detected_device.is_accessory_mode:
                    return True
            time.sleep(0.3)
        return False

    def open_stream(
        self,
        device: AoaDetectedDevice,
    ) -> tuple[AoaReadStream, AoaWriteStream]:
        self._require_pyusb()
        usb_util = self._usb_util
        if usb_util is None:
            raise RuntimeError("AOA host driver were not initialized with a USB utility module.")

        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA host could not find the selected USB device handle.")

        try:
            device_handle.set_configuration()
            configuration = device_handle.get_active_configuration()
            interface = configuration[(0, 0)]
            usb_util.claim_interface(device_handle, interface.bInterfaceNumber)

            endpoint_out = usb_util.find_descriptor(
                interface,
                custom_match=lambda endpoint: (
                    usb_util.endpoint_direction(endpoint.bEndpointAddress)
                    == usb_util.ENDPOINT_OUT
                ),
            )
            endpoint_in = usb_util.find_descriptor(
                interface,
                custom_match=lambda endpoint: (
                    usb_util.endpoint_direction(endpoint.bEndpointAddress)
                    == usb_util.ENDPOINT_IN
                ),
            )
            if endpoint_out is None or endpoint_in is None:
                usb_util.release_interface(device_handle, interface.bInterfaceNumber)
                usb_util.dispose_resources(device_handle)
                raise RuntimeError(
                    "AOA accessory interface does not expose both IN and OUT bulk endpoints."
                )
        except self._usb_error_type as exc:
            usb_util.dispose_resources(device_handle)
            raise RuntimeError(f"AOA stream setup failed: {exc}") from exc

        self._active_device = device
        self._active_handle = device_handle
        self._state = AoaHostState.CONNECTED
        return (
            _PyUsbAoaReadStream(
                device_handle=device_handle,
                endpoint=endpoint_in,
                usb_error_type=self._usb_error_type,
            ),
            _PyUsbAoaWriteStream(
                device_handle=device_handle,
                endpoint=endpoint_out,
                usb_error_type=self._usb_error_type,
            ),
        )

    def _require_pyusb(self) -> None:
        if self._usb_core is None or self._usb_util is None:
            raise RuntimeError(
                "AOA host driver require pyusb (install with `python -m pip install pyusb`)."
            )

    def _find_device_handle(self, device: AoaDetectedDevice) -> Any | None:
        self._require_pyusb()
        usb_core = self._usb_core
        if usb_core is None:
            raise RuntimeError("AOA host driver were not initialized with a USB core module.")
        found = usb_core.find(
            idVendor=device.vendor_id,
            idProduct=device.product_id,
            bus=device.bus,
            address=device.address,
        )
        if found is not None:
            return found
        return usb_core.find(idVendor=device.vendor_id, idProduct=device.product_id)

    def _supports_aoa_protocol(self, device_handle: Any) -> bool:
        try:
            protocol_response = device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_IN,
                AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=600,
            )
            return len(protocol_response) == 2
        except self._usb_error_type:
            return False

    def _serial_number(self, device_handle: Any) -> str | None:
        try:
            value = getattr(device_handle, "serial_number", None)
            if value:
                return str(value)
        except self._usb_error_type:
            pass
        return None

    def _device_id(self, device_handle: Any, serial: str | None) -> str:
        if serial:
            return serial
        bus = getattr(device_handle, "bus", "unknown")
        address = getattr(device_handle, "address", "unknown")
        return f"usb-{bus}-{address}"

    def _release_active_handle(self) -> None:
        handle = self._active_handle
        usb_util = self._usb_util
        self._active_handle = None
        self._active_device = None
        if handle is None or usb_util is None:
            return
        try:
            configuration = handle.get_active_configuration()
            interface = configuration[(0, 0)]
            usb_util.release_interface(handle, interface.bInterfaceNumber)
        except Exception:  # noqa: BLE001
            pass
        finally:
            try:
                usb_util.dispose_resources(handle)
            except Exception:  # noqa: BLE001
                pass


class _PyUsbAoaReadStream:
    """Readable wrapper around a PyUSB IN bulk endpoint."""

    def __init__(
        self,
        *,
        device_handle: Any,
        endpoint: Any,
        usb_error_type: type[BaseException],
    ) -> None:
        self._device_handle = device_handle
        self._endpoint = endpoint
        self._usb_error_type = usb_error_type
        self._closed = False

    def read(self, size: int = -1, timeout: float | None = None) -> bytes:
        if self._closed:
            return b""
        if size == 0:
            return b""
        read_size = self._endpoint.wMaxPacketSize if size < 0 else size
        read_timeout = 5000 if timeout is None else int(timeout * 1000)
        try:
            return bytes(
                self._device_handle.read(
                    self._endpoint.bEndpointAddress,
                    read_size,
                    timeout=read_timeout,
                )
            )
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA stream read failed: {exc}") from exc

    def close(self) -> None:
        self._closed = True


class _PyUsbAoaWriteStream:
    """Writable wrapper around a PyUSB OUT bulk endpoint."""

    def __init__(
        self,
        *,
        device_handle: Any,
        endpoint: Any,
        usb_error_type: type[BaseException],
    ) -> None:
        self._device_handle = device_handle
        self._endpoint = endpoint
        self._usb_error_type = usb_error_type
        self._closed = False

    def write(self, data: bytes) -> int:
        if self._closed:
            raise RuntimeError("Cannot write to a closed AOA stream.")
        try:
            return int(
                self._device_handle.write(
                    self._endpoint.bEndpointAddress,
                    data,
                    timeout=5000,
                )
            )
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA stream write failed: {exc}") from exc

    def close(self) -> None:
        self._closed = True
