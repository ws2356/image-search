from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import hashlib
import hmac
import json
import threading
from typing import Callable

from dt_image_search.mobile.transport.contracts import (
    MobileTransportContext,
    MobileTransportKind,
    MobileTransportResponse,
)
from dt_image_search.mobile.transport.router import (
    MobileTransportRouteNotFoundError,
    MobileTransportRouter,
)
from dt_image_search.mobile.transport.usb_tunnel import (
    Pymobiledevice3UsbTunnelProvider,
    UsbConnectedDevice,
    UsbTunnelConnectError,
    UsbTunnelProvider,
    UsbTunnelUnavailableError,
)

MOBILE_TRANSPORT_ENVELOPE_SCHEMA = "dtis.mobile-transport.v1"


class UsbTransportState(str, Enum):
    STOPPED = "stopped"
    CONFIGURED = "configured"
    READY = "ready"
    CONNECTED = "connected"


@dataclass(frozen=True)
class UsbBootstrapConfig:
    session_id: str
    one_time_passcode: str
    suggested_port: int
    fallback_port_window: int = 20

    def __post_init__(self) -> None:
        if not self.session_id.strip():
            raise ValueError("USB bootstrap session_id must be a non-empty string.")
        if not self.one_time_passcode.strip():
            raise ValueError("USB bootstrap one_time_passcode must be a non-empty string.")
        if self.suggested_port <= 0 or self.suggested_port > 65535:
            raise ValueError("USB bootstrap suggested_port must be in range 1..65535.")
        if self.fallback_port_window < 0:
            raise ValueError("USB bootstrap fallback_port_window must be non-negative.")


@dataclass(frozen=True)
class UsbTunnelTarget:
    device_udid: str
    remote_port: int


def iter_usb_probe_ports(
    *,
    suggested_port: int,
    fallback_port_window: int,
) -> tuple[int, ...]:
    if suggested_port <= 0 or suggested_port > 65535:
        raise ValueError("USB suggested port must be in range 1..65535.")
    if fallback_port_window < 0:
        raise ValueError("USB fallback port window must be non-negative.")

    candidate_ports: list[int] = [suggested_port]
    for offset in range(1, fallback_port_window + 1):
        higher_port = suggested_port + offset
        if higher_port <= 65535:
            candidate_ports.append(higher_port)
        lower_port = suggested_port - offset
        if lower_port >= 1:
            candidate_ports.append(lower_port)
    return tuple(candidate_ports)


class UsbWebSocketTransportAdapter:
    def __init__(
        self,
        *,
        router: MobileTransportRouter,
        log_handler: Callable[..., None],
        tunnel_provider: UsbTunnelProvider | None = None,
    ):
        self._router = router
        self._log_handler = log_handler
        self._tunnel_provider = tunnel_provider or Pymobiledevice3UsbTunnelProvider()
        self._lock = threading.RLock()
        self._state = UsbTransportState.STOPPED
        self._bootstrap_config: UsbBootstrapConfig | None = None
        self._active_tunnel_target: UsbTunnelTarget | None = None
        self._last_probe_error: str | None = None

    @property
    def state(self) -> UsbTransportState:
        with self._lock:
            return self._state

    @property
    def bootstrap_config(self) -> UsbBootstrapConfig | None:
        with self._lock:
            return self._bootstrap_config

    @property
    def active_tunnel_target(self) -> UsbTunnelTarget | None:
        with self._lock:
            return self._active_tunnel_target

    @property
    def last_probe_error(self) -> str | None:
        with self._lock:
            return self._last_probe_error

    def configure_bootstrap(self, config: UsbBootstrapConfig) -> None:
        with self._lock:
            self._bootstrap_config = config
            self._state = UsbTransportState.CONFIGURED
            self._active_tunnel_target = None
            self._last_probe_error = None
        self._safe_log(
            "info",
            message=(
                "UsbWebSocketTransportAdapter/configure_bootstrap: "
                f"session_id={config.session_id} suggested_port={config.suggested_port} "
                f"fallback_window={config.fallback_port_window}"
            ),
        )

    def start(self) -> None:
        config = self._require_bootstrap_config()
        with self._lock:
            self._state = UsbTransportState.READY
            self._active_tunnel_target = None
            self._last_probe_error = None
        self._probe_usb_tunnel(config)

    def mark_connected(self) -> None:
        with self._lock:
            if self._state == UsbTransportState.STOPPED:
                raise RuntimeError("USB transport must be started before marking connected.")
            self._state = UsbTransportState.CONNECTED

    def stop(self) -> None:
        with self._lock:
            self._state = UsbTransportState.STOPPED
            self._active_tunnel_target = None
            self._last_probe_error = None

    def build_auth_digest(self, rand: str) -> str:
        config = self._require_bootstrap_config()
        material = f"{config.one_time_passcode}{rand}".encode("utf-8")
        return hashlib.sha256(material).hexdigest()

    def verify_auth_digest(self, *, rand: str, provided_digest: str) -> bool:
        expected_digest = self.build_auth_digest(rand)
        return hmac.compare_digest(expected_digest, provided_digest)

    def dispatch_text_envelope(
        self,
        raw_message: str,
        *,
        remote_address: str | None = None,
    ) -> MobileTransportResponse:
        parsed_envelope = self._parse_envelope(raw_message)
        if isinstance(parsed_envelope, MobileTransportResponse):
            return parsed_envelope

        operation = parsed_envelope["operation"]
        request_id = parsed_envelope.get("request_id")
        body = parsed_envelope.get("body")
        if body is None:
            body = {}
        context = MobileTransportContext(
            transport=MobileTransportKind.USB_WEBSOCKET,
            operation=operation,
            request_id=request_id,
            remote_address=remote_address,
        )

        try:
            return self._router.dispatch(
                operation=operation,
                payload=body,
                context=context,
            )
        except MobileTransportRouteNotFoundError:
            return self._transport_error_response(
                message=f"Desktop does not support USB transport operation '{operation}'.",
            )

    def _parse_envelope(self, raw_message: str) -> dict[str, object] | MobileTransportResponse:
        try:
            parsed_value = json.loads(raw_message)
        except json.JSONDecodeError:
            return self._transport_error_response(
                message="Desktop could not parse the USB transport envelope JSON payload.",
            )

        if not isinstance(parsed_value, dict):
            return self._transport_error_response(
                message="Desktop requires JSON object envelopes for USB transport messages.",
            )

        schema = parsed_value.get("schema")
        if schema != MOBILE_TRANSPORT_ENVELOPE_SCHEMA:
            return self._transport_error_response(
                message="Desktop rejected an unsupported USB transport schema.",
            )

        operation = parsed_value.get("operation")
        if not isinstance(operation, str) or not operation.strip():
            return self._transport_error_response(
                message="Desktop rejected a USB transport message with a missing operation.",
            )

        return parsed_value

    def _transport_error_response(self, *, message: str) -> MobileTransportResponse:
        return MobileTransportResponse(
            status_code=400,
            payload={
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "status": "rejected",
                "message": message,
            },
        )

    def _require_bootstrap_config(self) -> UsbBootstrapConfig:
        with self._lock:
            if self._bootstrap_config is None:
                raise RuntimeError("USB bootstrap config is not available.")
            return self._bootstrap_config

    def _probe_usb_tunnel(self, config: UsbBootstrapConfig) -> None:
        try:
            usb_devices = self._tunnel_provider.list_usb_devices()
        except (UsbTunnelUnavailableError, UsbTunnelConnectError) as exc:
            self._set_probe_error(str(exc))
            self._safe_log(
                "warning",
                message=f"UsbWebSocketTransportAdapter/start: USB probing unavailable: {exc}",
            )
            return

        if not usb_devices:
            self._safe_log(
                "debug",
                message=(
                    "UsbWebSocketTransportAdapter/start: no USB device detected; "
                    "keeping LAN as active fallback transport."
                ),
            )
            return

        candidate_ports = iter_usb_probe_ports(
            suggested_port=config.suggested_port,
            fallback_port_window=config.fallback_port_window,
        )
        for usb_device in usb_devices:
            connected_target = self._probe_device_for_ports(
                usb_device=usb_device,
                candidate_ports=candidate_ports,
            )
            if connected_target is None:
                continue

            with self._lock:
                self._state = UsbTransportState.CONNECTED
                self._active_tunnel_target = connected_target
                self._last_probe_error = None
            self._safe_log(
                "info",
                message=(
                    "UsbWebSocketTransportAdapter/start: connected USB tunnel candidate "
                    f"device={connected_target.device_udid} port={connected_target.remote_port}"
                ),
            )
            return

        self._set_probe_error("Desktop could not connect to any USB bootstrap port candidates.")
        self._safe_log(
            "debug",
            message=(
                "UsbWebSocketTransportAdapter/start: USB devices detected but none accepted "
                "the bootstrap probe; keeping LAN fallback active."
            ),
        )

    def _probe_device_for_ports(
        self,
        *,
        usb_device: UsbConnectedDevice,
        candidate_ports: tuple[int, ...],
    ) -> UsbTunnelTarget | None:
        for port in candidate_ports:
            if self._tunnel_provider.probe_device_port(udid=usb_device.udid, port=port):
                return UsbTunnelTarget(
                    device_udid=usb_device.udid,
                    remote_port=port,
                )
        return None

    def _set_probe_error(self, message: str) -> None:
        with self._lock:
            self._last_probe_error = message

    def _safe_log(
        self,
        severity: str,
        *,
        message: str,
        error_type: str = "",
        where: str = "",
    ) -> None:
        try:
            self._log_handler(
                severity,
                error_type=error_type,
                where=where,
                message=message,
            )
        except Exception:
            return
