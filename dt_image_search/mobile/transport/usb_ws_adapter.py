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


class UsbWebSocketTransportAdapter:
    def __init__(
        self,
        *,
        router: MobileTransportRouter,
        log_handler: Callable[..., None],
    ):
        self._router = router
        self._log_handler = log_handler
        self._lock = threading.RLock()
        self._state = UsbTransportState.STOPPED
        self._bootstrap_config: UsbBootstrapConfig | None = None

    @property
    def state(self) -> UsbTransportState:
        with self._lock:
            return self._state

    @property
    def bootstrap_config(self) -> UsbBootstrapConfig | None:
        with self._lock:
            return self._bootstrap_config

    def configure_bootstrap(self, config: UsbBootstrapConfig) -> None:
        with self._lock:
            self._bootstrap_config = config
            self._state = UsbTransportState.CONFIGURED
        self._safe_log(
            "info",
            message=(
                "UsbWebSocketTransportAdapter/configure_bootstrap: "
                f"session_id={config.session_id} suggested_port={config.suggested_port} "
                f"fallback_window={config.fallback_port_window}"
            ),
        )

    def start(self) -> None:
        with self._lock:
            if self._bootstrap_config is None:
                raise RuntimeError("USB transport cannot start before bootstrap config is provided.")
            self._state = UsbTransportState.READY

    def mark_connected(self) -> None:
        with self._lock:
            if self._state == UsbTransportState.STOPPED:
                raise RuntimeError("USB transport must be started before marking connected.")
            self._state = UsbTransportState.CONNECTED

    def stop(self) -> None:
        with self._lock:
            self._state = UsbTransportState.STOPPED

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
