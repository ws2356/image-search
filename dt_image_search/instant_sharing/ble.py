from __future__ import annotations

import ipaddress
import threading
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Mapping

from dt_image_search.instant_sharing.contracts import InstantShareMetadata


INSTANT_SHARE_GATT_SERVICE_NAME = "instant-sharing"
INSTANT_SHARE_GATT_SERVICE_UUID = "4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b"
DEVICE_NAME_CHARACTERISTIC = "DeviceName"
DEVICE_SIGNATURE_CHARACTERISTIC = "DeviceSignature"
CONNECTION_CONFIG_CHARACTERISTIC = "ConnectionConfig"


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