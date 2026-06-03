from __future__ import annotations

import asyncio
import ipaddress
import json
import logging
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Callable, Mapping

from bless import (
    BlessGATTCharacteristic,
    BlessServer,
    GATTAttributePermissions,
    GATTCharacteristicProperties,
)

from dt_image_search.instant_sharing.contracts import InstantShareMetadata


_logger = logging.getLogger(__name__)


INSTANT_SHARE_GATT_SERVICE_NAME = "instant-sharing"
INSTANT_SHARE_GATT_SERVICE_UUID = "4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b"
DEVICE_NAME_CHARACTERISTIC = "DeviceName"
DEVICE_SIGNATURE_CHARACTERISTIC = "DeviceSignature"
CONNECTION_CONFIG_CHARACTERISTIC = "ConnectionConfig"

DEVICE_NAME_CHARACTERISTIC_UUID = "a1b2c3d4-1111-2222-3333-444455556601"
DEVICE_SIGNATURE_CHARACTERISTIC_UUID = "a1b2c3d4-1111-2222-3333-444455556602"
CONNECTION_CONFIG_CHARACTERISTIC_UUID = "8c1f1c8a-6e2e-4cf2-bff7-6cbad77b0f8b"


class CharacteristicAccessMode(str, Enum):
    READ_ONLY = "read_only"
    WRITE_ONLY = "write_only"


class CharacteristicAccessError(RuntimeError):
    pass


@dataclass(frozen=True)
class DeviceNameAdvertisement:
    device_name: str
    receiver_id: str

    def as_dict(self) -> dict[str, str]:
        return {
            "device_name": self.device_name,
            "receiver_id": self.receiver_id,
        }


@dataclass(frozen=True)
class DeviceSignatureAdvertisement:
    signature: str
    signature_key_id: str
    timestamp_ms: int

    def validate(self) -> None:
        if not self.signature.strip():
            raise ValueError("signature must not be empty.")
        if not self.signature_key_id.strip():
            raise ValueError("signature_key_id must not be empty.")
        if self.timestamp_ms <= 0:
            raise ValueError("timestamp_ms must be positive.")

    def as_dict(self) -> dict[str, object]:
        self.validate()
        return {
            "signature": self.signature,
            "signature_key_id": self.signature_key_id,
            "timestamp_ms": self.timestamp_ms,
        }


@dataclass(frozen=True)
class GattCharacteristicDefinition:
    name: str
    access_mode: CharacteristicAccessMode


@dataclass(frozen=True)
class ConnectionConfig:
    session_id: str
    mobile_port: int
    mobile_ip_list: tuple[str, ...]
    correlation_id: str
    metadata: InstantShareMetadata

    def validate(self) -> None:
        from uuid import UUID

        UUID(self.session_id)
        UUID(self.correlation_id)
        if self.mobile_port <= 0 or self.mobile_port > 65535:
            raise ValueError("mobile_port must be between 1 and 65535.")
        if not self.mobile_ip_list:
            raise ValueError("mobile_ip_list must contain at least one IP address.")
        for ip_value in self.mobile_ip_list:
            ipaddress.ip_address(ip_value)
        self.metadata.validate()

    def as_dict(self) -> dict[str, object]:
        self.validate()
        return {
            "session_id": self.session_id,
            "mobile_port": self.mobile_port,
            "mobile_ip_list": list(self.mobile_ip_list),
            "correlation_id": self.correlation_id,
            **self.metadata.as_dict(),
        }

    @classmethod
    def from_dict(cls, raw: Mapping[str, object]) -> "ConnectionConfig":
        metadata = InstantShareMetadata.from_dict(raw)
        mobile_port_raw = raw.get("mobile_port")
        if not isinstance(mobile_port_raw, int):
            raise ValueError("mobile_port must be an integer.")
        ip_list_raw = raw.get("mobile_ip_list")
        if not isinstance(ip_list_raw, (list, tuple)):
            raise ValueError("mobile_ip_list must be a list of IP addresses.")
        ip_list = tuple(str(item) for item in ip_list_raw)
        config = cls(
            session_id=str(raw.get("session_id", "")).strip(),
            mobile_port=mobile_port_raw,
            mobile_ip_list=ip_list,
            correlation_id=str(raw.get("correlation_id", "")).strip(),
            metadata=metadata,
        )
        config.validate()
        return config


class InstantShareBleService:
    def __init__(
        self,
        *,
        device_name_provider: Callable[[], DeviceNameAdvertisement],
        signature_provider: Callable[[], DeviceSignatureAdvertisement],
        bootstrap_handler: Callable[[ConnectionConfig], None],
    ) -> None:
        self._device_name_provider = device_name_provider
        self._signature_provider = signature_provider
        self._bootstrap_handler = bootstrap_handler
        self._active_connection_config: ConnectionConfig | None = None
        self._lock = threading.RLock()
        self._characteristics = (
            GattCharacteristicDefinition(DEVICE_NAME_CHARACTERISTIC, CharacteristicAccessMode.READ_ONLY),
            GattCharacteristicDefinition(DEVICE_SIGNATURE_CHARACTERISTIC, CharacteristicAccessMode.READ_ONLY),
            GattCharacteristicDefinition(CONNECTION_CONFIG_CHARACTERISTIC, CharacteristicAccessMode.WRITE_ONLY),
        )

    def list_characteristics(self) -> tuple[GattCharacteristicDefinition, ...]:
        return self._characteristics

    def read_characteristic(self, name: str) -> dict[str, object]:
        if name == DEVICE_NAME_CHARACTERISTIC:
            return self._device_name_provider().as_dict()
        if name == DEVICE_SIGNATURE_CHARACTERISTIC:
            return self._signature_provider().as_dict()
        if name == CONNECTION_CONFIG_CHARACTERISTIC:
            raise CharacteristicAccessError(f"{CONNECTION_CONFIG_CHARACTERISTIC} is write-only.")
        raise KeyError(name)

    def write_characteristic(self, name: str, value: Mapping[str, object]) -> None:
        if name != CONNECTION_CONFIG_CHARACTERISTIC:
            if name in {DEVICE_NAME_CHARACTERISTIC, DEVICE_SIGNATURE_CHARACTERISTIC}:
                raise CharacteristicAccessError(f"{name} is read-only.")
            raise KeyError(name)
        connection_config = ConnectionConfig.from_dict(value)
        self._bootstrap_handler(connection_config)
        with self._lock:
            self._active_connection_config = connection_config

    @property
    def active_connection_config(self) -> ConnectionConfig | None:
        with self._lock:
            return self._active_connection_config


class InstantShareBleDaemon:
    def __init__(
        self,
        *,
        ble_service: InstantShareBleService,
        is_enabled: Callable[[], bool],
        heartbeat: Callable[[], None] | None = None,
        poll_interval_seconds: float = 0.1,
        ble_server: InstantShareBlessServer | None = None,
    ) -> None:
        self._ble_service = ble_service
        self._is_enabled = is_enabled
        self._heartbeat = heartbeat
        self._poll_interval_seconds = poll_interval_seconds
        self._ble_server = ble_server
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.RLock()

    @property
    def ble_service(self) -> InstantShareBleService:
        return self._ble_service

    @property
    def ble_server(self) -> InstantShareBlessServer | None:
        return self._ble_server

    @property
    def is_running(self) -> bool:
        with self._lock:
            return self._thread is not None and self._thread.is_alive()

    def start(self) -> bool:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return True
            if not self._is_enabled():
                return False
            self._stop_event = threading.Event()
            self._thread = threading.Thread(
                target=self._run_loop,
                name="instant_share_ble_daemon",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        return True

    def stop(self) -> None:
        with self._lock:
            thread = self._thread
            self._thread = None
            self._stop_event.set()
            ble_server = self._ble_server
        if ble_server is not None:
            ble_server.stop()
        if thread is not None:
            thread.join(timeout=max(self._poll_interval_seconds, 0.1) * 5)

    def _run_loop(self) -> None:
        if self._ble_server is not None:
            if not self._ble_server.start():
                with self._lock:
                    self._thread = None
                return
        while not self._stop_event.is_set():
            if self._heartbeat is not None:
                self._heartbeat()
            if self._stop_event.wait(self._poll_interval_seconds):
                break


class InstantShareBlessServer:
    """BLE GATT server wrapper around ``bless.BlessServer``.

    Advertises the instant-sharing GATT service and exposes the three
    characteristics required by the iOS instant-share scanner. Read
    characteristics (DeviceName, DeviceSignature) are served from the
    providers attached to an :class:`InstantShareBleService`; the
    ConnectionConfig write is forwarded to its ``bootstrap_handler``.
    """

    def __init__(
        self,
        *,
        ble_service: InstantShareBleService,
        advertised_name: str = INSTANT_SHARE_GATT_SERVICE_NAME,
        service_uuid: str = INSTANT_SHARE_GATT_SERVICE_UUID,
    ) -> None:
        self._ble_service = ble_service
        self._advertised_name = advertised_name
        self._service_uuid = service_uuid
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._server: BlessServer | None = None
        self._ready_event = threading.Event()
        self._stop_event = threading.Event()
        self._lock = threading.RLock()
        self._last_error: BaseException | None = None

    @property
    def is_advertising(self) -> bool:
        with self._lock:
            server = self._server
            loop = self._loop
        if server is None or loop is None or loop.is_closed():
            return False
        try:
            future = asyncio.run_coroutine_threadsafe(server.is_advertising(), loop)
            return bool(future.result(timeout=1.0))
        except Exception:
            return False

    @property
    def is_running(self) -> bool:
        with self._lock:
            thread = self._thread
        return thread is not None and thread.is_alive()

    @property
    def last_error(self) -> BaseException | None:
        with self._lock:
            return self._last_error

    def start(self, *, timeout_seconds: float = 10.0) -> bool:
        _logger.info(
            "[InstantShareBlessServer] start() called, advertised_name=%s service_uuid=%s",
            self._advertised_name,
            self._service_uuid,
        )
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                _logger.info("[InstantShareBlessServer] already running, returning True")
                return True
            self._ready_event = threading.Event()
            self._stop_event = threading.Event()
            self._last_error = None
            self._thread = threading.Thread(
                target=self._run_loop,
                name="instant_share_bless_server",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info("[InstantShareBlessServer] thread started, waiting for ready event")
        if not self._ready_event.wait(timeout=timeout_seconds):
            _logger.warning(
                "[InstantShareBlessServer] did not become ready within %.1fs; "
                "Bluetooth may be unavailable or permission may not be granted.",
                timeout_seconds,
            )
            return False
        with self._lock:
            if self._last_error is not None:
                _logger.error(
                    "[InstantShareBlessServer] start completed with error: %s: %s",
                    type(self._last_error).__name__,
                    self._last_error,
                )
                return False
            # Bless may report is_advertising transiently False immediately after
            # server.start() returns. Poll briefly to confirm the server is
            # actually broadcasting before declaring success.
            deadline = time.monotonic() + 2.0
            ad_status = self.is_advertising
            while not ad_status and time.monotonic() < deadline:
                time.sleep(0.1)
                ad_status = self.is_advertising
            _logger.info(
                "[InstantShareBlessServer] start() succeeded, is_advertising=%s (after settle)",
                ad_status,
            )
            return True

    def stop(self, *, timeout_seconds: float = 5.0) -> None:
        with self._lock:
            thread = self._thread
            self._thread = None
            self._stop_event.set()
            server = self._server
            loop = self._loop
        if server is not None and loop is not None and not loop.is_closed():
            try:
                future = asyncio.run_coroutine_threadsafe(server.stop(), loop)
                future.result(timeout=timeout_seconds)
            except Exception as exc:
                _logger.debug("Bless server stop() raised: %s", exc)
        with self._lock:
            self._server = None
            self._loop = None
        if thread is not None:
            thread.join(timeout=timeout_seconds + 1.0)

    def _run_loop(self) -> None:
        _logger.info("[InstantShareBlessServer] _run_loop entered")
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            with self._lock:
                self._loop = loop
            _logger.info("[InstantShareBlessServer] created asyncio loop, constructing BlessServer")
            server = BlessServer(name=self._advertised_name, loop=loop)
            server.read_request_func = self._on_read_request
            server.write_request_func = self._on_write_request
            with self._lock:
                self._server = server
            _logger.info("[InstantShareBlessServer] BlessServer constructed, building/advertising")
            loop.run_until_complete(self._build_and_advertise(server))
            self._ready_event.set()
            _logger.info("[InstantShareBlessServer] _build_and_advertise completed, entering run_forever")
            loop.run_forever()
            _logger.info("[InstantShareBlessServer] run_forever returned")
        except BaseException as exc:  # noqa: BLE001
            with self._lock:
                self._last_error = exc
            _logger.exception(
                "[InstantShareBlessServer] _run_loop terminated with error: %s: %s",
                type(exc).__name__,
                exc,
            )
            self._ready_event.set()
        finally:
            try:
                loop = asyncio.get_event_loop()
                if not loop.is_closed():
                    loop.close()
            except Exception:
                pass
            with self._lock:
                self._server = None
                self._loop = None
            _logger.info("[InstantShareBlessServer] _run_loop exited")

    async def _build_and_advertise(self, server: BlessServer) -> None:
        _logger.info("[InstantShareBlessServer] adding service %s", self._service_uuid)
        await server.add_new_service(self._service_uuid)
        _logger.info("[InstantShareBlessServer] adding DeviceName characteristic %s", DEVICE_NAME_CHARACTERISTIC_UUID)
        await server.add_new_characteristic(
            self._service_uuid,
            DEVICE_NAME_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.read,
            None,
            GATTAttributePermissions.readable,
        )
        _logger.info("[InstantShareBlessServer] adding DeviceSignature characteristic %s", DEVICE_SIGNATURE_CHARACTERISTIC_UUID)
        await server.add_new_characteristic(
            self._service_uuid,
            DEVICE_SIGNATURE_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.read,
            None,
            GATTAttributePermissions.readable,
        )
        _logger.info("[InstantShareBlessServer] adding ConnectionConfig characteristic %s", CONNECTION_CONFIG_CHARACTERISTIC_UUID)
        await server.add_new_characteristic(
            self._service_uuid,
            CONNECTION_CONFIG_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.write,
            None,
            GATTAttributePermissions.writeable,
        )
        if self._stop_event.is_set():
            _logger.warning("[InstantShareBlessServer] stop requested before advertising started")
            return
        _logger.info("[InstantShareBlessServer] calling server.start() to begin advertising")
        await server.start()
        _logger.info("[InstantShareBlessServer] server.start() returned, is_advertising=%s", await server.is_advertising())

    def _on_read_request(
        self, characteristic: BlessGATTCharacteristic, **_kwargs: Any
    ) -> bytearray:
        uuid = str(characteristic.uuid).upper()
        _logger.info("[InstantShareBlessServer] read_request for char UUID=%s", uuid)
        if uuid == DEVICE_NAME_CHARACTERISTIC_UUID.upper():
            payload = self._ble_service.read_characteristic(DEVICE_NAME_CHARACTERISTIC)
        elif uuid == DEVICE_SIGNATURE_CHARACTERISTIC_UUID.upper():
            payload = self._ble_service.read_characteristic(DEVICE_SIGNATURE_CHARACTERISTIC)
        else:
            _logger.error("[InstantShareBlessServer] unsupported read UUID=%s", uuid)
            raise KeyError(f"Unsupported read characteristic UUID: {uuid}")
        encoded = bytearray(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
        _logger.info(
            "[InstantShareBlessServer] read_request returning %d bytes for UUID=%s",
            len(encoded),
            uuid,
        )
        return encoded

    def _on_write_request(
        self,
        characteristic: BlessGATTCharacteristic,
        value: Any,
        **_kwargs: Any,
    ) -> None:
        uuid = str(characteristic.uuid).upper()
        _logger.info(
            "[InstantShareBlessServer] write_request for char UUID=%s, %d bytes",
            uuid,
            len(value) if hasattr(value, "__len__") else -1,
        )
        if uuid != CONNECTION_CONFIG_CHARACTERISTIC_UUID.upper():
            _logger.error("[InstantShareBlessServer] unsupported write UUID=%s", uuid)
            raise ValueError(f"Unsupported write characteristic UUID: {uuid}")
        decoded: Any
        if isinstance(value, (bytes, bytearray)):
            decoded = json.loads(bytes(value).decode("utf-8"))
        elif isinstance(value, str):
            decoded = json.loads(value)
        else:
            decoded = value
        if not isinstance(decoded, Mapping):
            _logger.error("[InstantShareBlessServer] ConnectionConfig payload is not a JSON object")
            raise ValueError("ConnectionConfig payload must be a JSON object.")
        _logger.info(
            "[InstantShareBlessServer] write_request forwarding ConnectionConfig session_id=%s",
            decoded.get("session_id", "<missing>"),
        )
        self._ble_service.write_characteristic(CONNECTION_CONFIG_CHARACTERISTIC, decoded)
        _logger.info("[InstantShareBlessServer] write_request completed, bootstrap_handler invoked")