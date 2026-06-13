from __future__ import annotations

import ipaddress
import json
import logging
import socket
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Callable, Mapping

from zeroconf import IPVersion, ServiceInfo, Zeroconf

from dt_image_search.instant_sharing.contracts import InstantShareMetadata


_logger = logging.getLogger(__name__)

INSTANT_SHARE_MDNS_SERVICE_TYPE = "_instantshare._tcp.local."
INSTANT_SHARE_MDNS_PORT = 9527
INSTANT_SHARE_TLS_PORT = 9528


def _local_ip_addresses() -> list[str]:
    addrs: list[str] = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
            addrs.append(info[4][0])
    except Exception:
        pass
    return [ip for ip in addrs if ip and ip != "127.0.0.1" and not ip.startswith("169.254.")]


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

    def read_characteristic(self, name: str) -> dict[str, object]:
        if name == "DeviceName":
            return self._device_name_provider().as_dict()
        if name == "DeviceSignature":
            return self._signature_provider().as_dict()
        raise KeyError(name)

    def handle_bootstrap(self, connection_config: ConnectionConfig) -> None:
        self._bootstrap_handler(connection_config)
        with self._lock:
            self._active_connection_config = connection_config

    @property
    def active_connection_config(self) -> ConnectionConfig | None:
        with self._lock:
            return self._active_connection_config


@dataclass(frozen=True)
class BootstrapRequest:
    session_id: str
    mobile_port: int
    mobile_ip_list: tuple[str, ...]
    correlation_id: str
    payload_class: str
    target_intent: str

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
        if self.payload_class not in ("text", "image"):
            raise ValueError(f"invalid payload_class: {self.payload_class}")
        if self.target_intent not in ("clipboard_only", "clipboard_or_file"):
            raise ValueError(f"invalid target_intent: {self.target_intent}")

    @classmethod
    def from_dict(cls, raw: Mapping[str, object]) -> "BootstrapRequest":
        ip_list_raw = raw.get("mobile_ip_list")
        if not isinstance(ip_list_raw, (list, tuple)):
            raise ValueError("mobile_ip_list must be a list of IP addresses.")
        ip_list = tuple(str(item) for item in ip_list_raw)
        mobile_port_raw = raw.get("mobile_port")
        if not isinstance(mobile_port_raw, int):
            raise ValueError("mobile_port must be an integer.")
        req = cls(
            session_id=str(raw.get("session_id", "")).strip(),
            mobile_port=mobile_port_raw,
            mobile_ip_list=ip_list,
            correlation_id=str(raw.get("correlation_id", "")).strip(),
            payload_class=str(raw.get("payload_class", "")).strip(),
            target_intent=str(raw.get("target_intent", "")).strip(),
        )
        req.validate()
        return req


class InstantShareMDNSAdvertiser:
    def __init__(
        self,
        *,
        ble_service: InstantShareBleService,
        device_id: str,
        desktop_name: str = "",
        port: int = INSTANT_SHARE_MDNS_PORT,
        tls_port: int = INSTANT_SHARE_TLS_PORT,
        protocol_version: str = "1",
    ) -> None:
        self._ble_service = ble_service
        self._device_id = device_id
        self._desktop_name = desktop_name or "AuSearch Desktop"
        self._port = port
        self._tls_port = tls_port
        self._protocol_version = protocol_version
        self._zeroconf: Zeroconf | None = None
        self._service_info: ServiceInfo | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._ready_event = threading.Event()
        self._lock = threading.RLock()
        self._last_error: BaseException | None = None

    @property
    def is_advertising(self) -> bool:
        with self._lock:
            zc = self._zeroconf
        return zc is not None

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
            "[InstantShareMDNSAdvertiser] start() called, desktop_name=%s device_id=%s port=%d",
            self._desktop_name,
            self._device_id,
            self._port,
        )
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                _logger.info("[InstantShareMDNSAdvertiser] already running, returning True")
                return True
            self._ready_event = threading.Event()
            self._stop_event = threading.Event()
            self._last_error = None
            self._thread = threading.Thread(
                target=self._run_loop,
                name="instant_share_mdns_advertiser",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info("[InstantShareMDNSAdvertiser] thread started, waiting for ready event")
        if not self._ready_event.wait(timeout=timeout_seconds):
            _logger.warning(
                "[InstantShareMDNSAdvertiser] did not become ready within %.1fs",
                timeout_seconds,
            )
            return False
        with self._lock:
            if self._last_error is not None:
                _logger.error(
                    "[InstantShareMDNSAdvertiser] start completed with error: %s: %s",
                    type(self._last_error).__name__,
                    self._last_error,
                )
                return False
            _logger.info(
                "[InstantShareMDNSAdvertiser] start() succeeded, is_advertising=%s",
                self.is_advertising,
            )
            return True

    def stop(self, *, timeout_seconds: float = 5.0) -> None:
        with self._lock:
            thread = self._thread
            self._thread = None
            self._stop_event.set()
            zeroconf = self._zeroconf
            self._zeroconf = None
            self._service_info = None
        if zeroconf is not None:
            zeroconf.close()
        if thread is not None:
            thread.join(timeout=timeout_seconds + 1.0)

    def _refresh_txt(self) -> None:
        with self._lock:
            zc = self._zeroconf
            info = self._service_info
        if zc is None or info is None:
            return
        try:
            properties = self._build_txt_properties()
            from zeroconf import ServiceInfo
            new_info = ServiceInfo(
                type_=INSTANT_SHARE_MDNS_SERVICE_TYPE,
                name=info.name,
                addresses=info.addresses,
                port=self._port,
                properties=properties,
            )
            zc.update_service(new_info)
            with self._lock:
                self._service_info = new_info
        except Exception:
            _logger.exception("[InstantShareMDNSAdvertiser] _refresh_txt failed")

    def _build_txt_properties(self) -> dict[str, str]:
        props: dict[str, str] = {
            "ver": self._protocol_version,
            "device_id": self._device_id,
            "tls_port": str(self._tls_port),
        }
        try:
            name_adv = self._ble_service.read_characteristic("DeviceName")
            props["device_name"] = str(name_adv.get("device_name", self._desktop_name))
        except Exception:
            props["device_name"] = self._desktop_name
        try:
            sig_adv = self._ble_service.read_characteristic("DeviceSignature")
            props["signature"] = str(sig_adv.get("signature", ""))
            props["signature_key_id"] = str(sig_adv.get("signature_key_id", ""))
            props["timestamp_ms"] = str(sig_adv.get("timestamp_ms", "0"))
        except Exception:
            props["signature"] = ""
            props["signature_key_id"] = ""
            props["timestamp_ms"] = "0"
        return props

    def _sanitize_service_name(self) -> str:
        name = self._desktop_name.strip()
        safe = "".join(c if c.isalnum() or c in "-_ " else "_" for c in name)
        return safe.rstrip("_").rstrip() or "AuSearchDesktop"

    def _run_loop(self) -> None:
        _logger.info("[InstantShareMDNSAdvertiser] _run_loop entered")
        try:
            zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            with self._lock:
                self._zeroconf = zeroconf
            _logger.info("[InstantShareMDNSAdvertiser] created Zeroconf instance")
            properties = self._build_txt_properties()
            _logger.info(
                "[InstantShareMDNSAdvertiser] built TXT properties: %s",
                properties,
            )
            addresses = [socket.inet_aton(addr) for addr in _local_ip_addresses()]
            _logger.info(
                "[InstantShareMDNSAdvertiser] local addresses: %s",
                [socket.inet_ntoa(addr) if isinstance(addr, bytes) else addr for addr in addresses],
            )
            service_name = self._sanitize_service_name()
            _logger.info("[InstantShareMDNSAdvertiser] service name: %s", service_name)
            service_info = ServiceInfo(
                type_=INSTANT_SHARE_MDNS_SERVICE_TYPE,
                name=f"{service_name}.{INSTANT_SHARE_MDNS_SERVICE_TYPE}",
                addresses=addresses,
                port=self._port,
                properties=properties,
            )
            with self._lock:
                self._service_info = service_info
            _logger.info("[InstantShareMDNSAdvertiser] registering service %s", service_info.name)
            zeroconf.register_service(service_info, ttl=120)
            _logger.info("[InstantShareMDNSAdvertiser] service registered, advertising started")
            self._ready_event.set()
            while not self._stop_event.is_set():
                if self._stop_event.wait(5.0):
                    break
            _logger.info("[InstantShareMDNSAdvertiser] stop event received, exiting")
        except BaseException as exc:
            with self._lock:
                self._last_error = exc
            _logger.exception(
                "[InstantShareMDNSAdvertiser] _run_loop terminated with error: %s: %s",
                type(exc).__name__,
                exc,
            )
            self._ready_event.set()
        finally:
            _logger.info("[InstantShareMDNSAdvertiser] _run_loop exited")


class InstantShareBleDaemon:
    def __init__(
        self,
        *,
        ble_service: InstantShareBleService,
        is_enabled: Callable[[], bool],
        heartbeat: Callable[[], None] | None = None,
        poll_interval_seconds: float = 0.1,
        mdns_advertiser: InstantShareMDNSAdvertiser | None = None,
    ) -> None:
        self._ble_service = ble_service
        self._is_enabled = is_enabled
        self._heartbeat = heartbeat
        self._poll_interval_seconds = poll_interval_seconds
        self._mdns_advertiser = mdns_advertiser
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.RLock()

    @property
    def ble_service(self) -> InstantShareBleService:
        return self._ble_service

    @property
    def mdns_advertiser(self) -> InstantShareMDNSAdvertiser | None:
        return self._mdns_advertiser

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
                name="instant_share_mdns_daemon",
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
            mdns_advertiser = self._mdns_advertiser
        if mdns_advertiser is not None:
            mdns_advertiser.stop()
        if thread is not None:
            thread.join(timeout=max(self._poll_interval_seconds, 0.1) * 5)

    def _run_loop(self) -> None:
        _started_mdns = False
        if self._mdns_advertiser is not None:
            def _start_mdns():
                try:
                    ok = self._mdns_advertiser.start()  # type: ignore[union-attr]
                    if not ok:
                        _logger.warning(
                            "[InstantShareBleDaemon] mDNS advertiser failed to start, continuing without advertising"
                        )
                except Exception:
                    _logger.exception(
                        "[InstantShareBleDaemon] mDNS advertiser start threw, continuing without advertising"
                    )
            threading.Thread(target=_start_mdns, name="instant_share_mdns_startup", daemon=True).start()
            _started_mdns = True
        while not self._stop_event.is_set():
            if self._heartbeat is not None:
                self._heartbeat()
            if self._stop_event.wait(self._poll_interval_seconds):
                break
