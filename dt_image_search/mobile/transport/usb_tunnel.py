from __future__ import annotations

import asyncio
from dataclasses import dataclass
import importlib
import inspect
import socket
from typing import Any, Protocol


class UsbTunnelUnavailableError(RuntimeError):
    """Raised when USB tunneling prerequisites are unavailable."""


class UsbTunnelDeviceNotFoundError(RuntimeError):
    """Raised when a requested USB device cannot be located."""


class UsbTunnelConnectError(RuntimeError):
    """Raised when desktop cannot open a USB tunnel socket."""


@dataclass(frozen=True)
class UsbConnectedDevice:
    udid: str
    connection_type: str = "USB"


class UsbTunnelProvider(Protocol):
    def list_usb_devices(self) -> tuple[UsbConnectedDevice, ...]:
        ...

    def probe_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> bool:
        ...

    def connect_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> socket.socket:
        ...


class Pymobiledevice3UsbTunnelProvider:
    def __init__(
        self,
        *,
        usbmux_module: Any | None = None,
        exceptions_module: Any | None = None,
    ):
        self._usbmux_module = usbmux_module
        self._exceptions_module = exceptions_module

    def list_usb_devices(self) -> tuple[UsbConnectedDevice, ...]:
        usbmux_module = self._require_usbmux_module()
        connection_errors = self._connection_error_types()
        try:
            devices = self._run_async(
                usbmux_module.select_devices_by_connection_type("USB"),
            )
        except connection_errors as exc:
            raise UsbTunnelConnectError("Desktop could not read USB device list from usbmuxd.") from exc
        except OSError as exc:
            raise UsbTunnelConnectError("Desktop failed while listing USB devices.") from exc
        connected_devices: list[UsbConnectedDevice] = []
        for device in devices:
            serial = str(getattr(device, "serial", "")).strip()
            if not serial:
                continue
            connection_type = str(getattr(device, "connection_type", "USB") or "USB")
            connected_devices.append(
                UsbConnectedDevice(
                    udid=serial,
                    connection_type=connection_type,
                )
            )
        return tuple(connected_devices)

    def probe_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> bool:
        try:
            connected_socket = self.connect_device_port(
                udid=udid,
                port=port,
                timeout_seconds=timeout_seconds,
            )
        except (
            UsbTunnelUnavailableError,
            UsbTunnelDeviceNotFoundError,
            UsbTunnelConnectError,
            OSError,
        ):
            return False

        connected_socket.close()
        return True

    def connect_device_port(
        self,
        *,
        udid: str,
        port: int,
        timeout_seconds: float = 1.0,
    ) -> socket.socket:
        normalized_udid = udid.strip()
        if not normalized_udid:
            raise ValueError("USB device udid must be a non-empty string.")
        _validate_port(port)
        if timeout_seconds <= 0:
            raise ValueError("USB tunnel timeout_seconds must be greater than zero.")

        usbmux_module = self._require_usbmux_module()
        connection_errors = self._connection_error_types()

        try:
            mux_device = self._run_async(
                usbmux_module.select_device(
                    normalized_udid,
                    connection_type="USB",
                ),
            )
        except connection_errors as exc:
            raise UsbTunnelConnectError(
                f"Desktop could not inspect USB device '{normalized_udid}' via usbmuxd.",
            ) from exc
        except Exception as exc:
            print(f"Unexpected error while selecting USB device '{normalized_udid}': {exc!r}")
            raise

        if mux_device is None:
            raise UsbTunnelDeviceNotFoundError(
                f"Desktop could not find USB device '{normalized_udid}'.",
            )

        try:
            connect_result = mux_device.connect(port)
            if inspect.isawaitable(connect_result):
                connected_socket = self._run_async(
                    asyncio.wait_for(
                        connect_result,
                        timeout=timeout_seconds,
                    ),
                )
            else:
                connected_socket = connect_result
        except connection_errors as exc:
            print(f"Unexpected error while connecting to USB device '{normalized_udid}' port {port}: {exc!r}")
            raise UsbTunnelConnectError(
                f"Desktop could not connect to USB device '{normalized_udid}' port {port}.",
            ) from exc
        except TimeoutError as exc:
            print(f"Unexpected error while connecting to USB device '{normalized_udid}' port {port}: {exc!r}")
            raise UsbTunnelConnectError(
                f"Desktop USB tunnel connection to '{normalized_udid}:{port}' timed out.",
            ) from exc
        except OSError as exc:
            print(f"Unexpected error while connecting to USB device '{normalized_udid}' port {port}: {exc!r}")
            raise UsbTunnelConnectError(
                f"Desktop USB tunnel socket failed for '{normalized_udid}:{port}'.",
            ) from exc
        except Exception as exc:
            print(f"Unexpected error while connecting to USB device '{normalized_udid}' port {port}: {exc!r}")
            raise

        if not isinstance(connected_socket, socket.socket):
            raise UsbTunnelConnectError(
                "Desktop USB tunnel provider did not return a socket connection.",
            )

        return connected_socket

    def _require_usbmux_module(self) -> Any:
        if self._usbmux_module is not None:
            return self._usbmux_module

        try:
            self._usbmux_module = importlib.import_module("pymobiledevice3.usbmux")
        except ImportError as exc:
            raise UsbTunnelUnavailableError(
                "Desktop USB transport requires pymobiledevice3 "
                "(install with `python3 -m pip install pymobiledevice3`).",
            ) from exc
        return self._usbmux_module

    def _connection_error_types(self) -> tuple[type[BaseException], ...]:
        exceptions_module = self._require_exceptions_module()
        connection_error_types: list[type[BaseException]] = []
        for exception_name in (
            "ConnectionFailedError",
            "MuxException",
            "ConnectionFailedToUsbmuxdError",
            "BadDevError",
        ):
            exception_value = getattr(exceptions_module, exception_name, None)
            if (
                isinstance(exception_value, type)
                and issubclass(exception_value, BaseException)
                and exception_value not in connection_error_types
            ):
                connection_error_types.append(exception_value)
        if not connection_error_types:
            return (RuntimeError,)
        return tuple(connection_error_types)

    def _require_exceptions_module(self) -> Any:
        if self._exceptions_module is not None:
            return self._exceptions_module
        try:
            self._exceptions_module = importlib.import_module("pymobiledevice3.exceptions")
        except ImportError as exc:
            raise UsbTunnelUnavailableError(
                "Desktop USB transport requires pymobiledevice3 exception classes.",
            ) from exc
        return self._exceptions_module

    @staticmethod
    def _run_async(awaitable: Any) -> Any:
        if not inspect.isawaitable(awaitable):
            return awaitable
        try:
            return asyncio.run(awaitable)
        except RuntimeError as exc:
            if "asyncio.run() cannot be called from a running event loop" in str(exc):
                raise UsbTunnelUnavailableError(
                    "Desktop USB tunnel calls cannot run from an active asyncio event loop.",
                ) from exc
            raise
        except Exception as exc:
            print(f"Unexpected error while running async USB tunnel operation: {exc!r}")
            raise


def _validate_port(port: int) -> None:
    if port <= 0 or port > 65535:
        raise ValueError("USB tunnel port must be in range 1..65535.")
