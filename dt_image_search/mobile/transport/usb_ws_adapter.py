from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import hashlib
import hmac
import json
import secrets
import socket
import threading
import time
from typing import Callable, Protocol

from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
    TRANSFER_ASSET_STREAM_STATE_COMPLETE,
    TRANSFER_ASSET_STREAM_STATE_FIELD,
    TRANSFER_ASSET_STREAM_STATE_START,
    TransferAssetUploadStream,
)
from dt_image_search.mobile.transport.contracts import (
    TRANSFER_ASSET_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
    MobileTransportResponse,
    TransferAssetUploadPayload,
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
USB_TRANSPORT_REJECTED_STATUS = "rejected"
USB_AUTH_CHALLENGE_OPERATION = "transport.auth.challenge"
USB_AUTH_CHALLENGE_BODY_SCHEMA = "dtis.mobile-pairing.v1"
USB_AUTH_CHALLENGE_REQUEST_ID = "auth-challenge"
USB_AUTH_CHALLENGE_TIMEOUT_SECONDS = 2.0

try:
    from websockets.exceptions import ConnectionClosed, WebSocketException
    from websockets.sync.client import connect as websocket_connect
except ImportError:  # pragma: no cover - exercised in environments without websockets.
    ConnectionClosed = RuntimeError  # type: ignore[assignment]
    WebSocketException = RuntimeError  # type: ignore[assignment]
    websocket_connect = None


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


class UsbWebSocketConnection(Protocol):
    def recv(self, timeout: float | None = None) -> str | bytes:
        ...

    def send(self, message: str) -> None:
        ...

    def close(self, code: int = 1000, reason: str = "") -> None:
        ...


def _default_websocket_connect(**kwargs: object) -> UsbWebSocketConnection:
    if websocket_connect is None:
        raise RuntimeError(
            "Desktop USB transport requires the websockets package "
            "(install with `python3 -m pip install websockets`)."
        )
    return websocket_connect(**kwargs)


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
        websocket_connect_fn: Callable[..., UsbWebSocketConnection] | None = None,
        probe_interval_seconds: float = 0.6,
        response_poll_timeout_seconds: float = 0.6,
    ):
        if probe_interval_seconds <= 0:
            raise ValueError("USB probe_interval_seconds must be greater than zero.")
        if response_poll_timeout_seconds <= 0:
            raise ValueError("USB response_poll_timeout_seconds must be greater than zero.")
        self._router = router
        self._log_handler = log_handler
        self._tunnel_provider = tunnel_provider or Pymobiledevice3UsbTunnelProvider()
        self._websocket_connect = websocket_connect_fn or _default_websocket_connect
        self._probe_interval_seconds = probe_interval_seconds
        self._response_poll_timeout_seconds = response_poll_timeout_seconds
        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._worker_thread: threading.Thread | None = None
        self._active_websocket_connection: UsbWebSocketConnection | None = None
        self._active_tunnel_socket: socket.socket | None = None
        self._asset_upload_stream = TransferAssetUploadStream()
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
            self._close_active_connection_locked()
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
        worker_thread: threading.Thread | None = None
        with self._lock:
            self._state = UsbTransportState.READY
            self._active_tunnel_target = None
            self._last_probe_error = None
            self._stop_event.clear()
            if self._worker_thread is None or not self._worker_thread.is_alive():
                worker_thread = threading.Thread(
                    target=self._run_transport_loop,
                    name="mobile-usb-transport",
                    daemon=True,
                )
                self._worker_thread = worker_thread
        if worker_thread is not None:
            worker_thread.start()
        self._safe_log(
            "debug",
            message=(
                "UsbWebSocketTransportAdapter/start: started USB probe loop "
                f"for session_id={config.session_id}"
            ),
        )

    def mark_connected(self) -> None:
        with self._lock:
            if self._state == UsbTransportState.STOPPED:
                raise RuntimeError("USB transport must be started before marking connected.")
            self._state = UsbTransportState.CONNECTED

    def stop(self) -> None:
        worker_thread: threading.Thread | None
        with self._lock:
            self._stop_event.set()
            worker_thread = self._worker_thread
            self._worker_thread = None
            self._close_active_connection_locked()
            self._state = UsbTransportState.STOPPED
            self._active_tunnel_target = None
            self._last_probe_error = None
        if worker_thread is not None and worker_thread.is_alive():
            worker_thread.join(timeout=2.0)

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
        _, response = self._dispatch_envelope_request(
            raw_message,
            remote_address=remote_address,
        )
        if response is None:
            return MobileTransportResponse(
                status_code=202,
                payload={
                    "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                    "status": "accepted",
                    "message": "Desktop accepted the transfer asset stream metadata.",
                },
            )
        return response

    def _run_transport_loop(self) -> None:
        while not self._stop_event.is_set():
            config = self.bootstrap_config
            if config is None:
                self._wait_for_retry_interval()
                continue

            tunnel_target = self._probe_usb_tunnel(config)
            if tunnel_target is None:
                self._set_ready_state()
                self._wait_for_retry_interval()
                continue

            try:
                self._run_websocket_session(
                    tunnel_target=tunnel_target,
                    config=config,
                )
            except (
                UsbTunnelUnavailableError,
                UsbTunnelConnectError,
                OSError,
                RuntimeError,
                TimeoutError,
                WebSocketException,
            ) as exc:
                self._set_probe_error(str(exc))
                self._safe_log(
                    "debug",
                    message=(
                        "UsbWebSocketTransportAdapter/_run_transport_loop: USB websocket connection "
                        f"failed for device={tunnel_target.device_udid} port={tunnel_target.remote_port}: {exc}"
                    ),
                )
            finally:
                self._set_ready_state()

            self._wait_for_retry_interval()

    def _run_websocket_session(
        self,
        *,
        tunnel_target: UsbTunnelTarget,
        config: UsbBootstrapConfig,
    ) -> None:
        connected_socket = self._tunnel_provider.connect_device_port(
            udid=tunnel_target.device_udid,
            port=tunnel_target.remote_port,
            timeout_seconds=1.2,
        )
        rand = secrets.token_hex(16)
        try:
            websocket_connection = self._websocket_connect(
                uri=f"ws://127.0.0.1:{tunnel_target.remote_port}",
                sock=connected_socket,
                additional_headers=(
                    ("x-dtis-session-id", config.session_id),
                    ("x-dtis-rand", rand),
                ),
                open_timeout=2.0,
                ping_interval=20.0,
                ping_timeout=20.0,
                proxy=None,
            )
        except (OSError, RuntimeError, TimeoutError, WebSocketException):
            connected_socket.close()
            raise
        remote_address = f"usb://{tunnel_target.device_udid}:{tunnel_target.remote_port}"
        with self._lock:
            self._state = UsbTransportState.READY
            self._active_tunnel_target = tunnel_target
            self._last_probe_error = None
            self._active_tunnel_socket = connected_socket
            self._active_websocket_connection = websocket_connection
        self._perform_auth_challenge(
            websocket_connection=websocket_connection,
            config=config,
        )
        with self._lock:
            if self._state != UsbTransportState.STOPPED:
                self._state = UsbTransportState.CONNECTED
        self._safe_log(
            "info",
            message=(
                "UsbWebSocketTransportAdapter/_run_websocket_session: USB websocket connected "
                "and authenticated "
                f"device={tunnel_target.device_udid} port={tunnel_target.remote_port}"
            ),
        )

        while not self._stop_event.is_set():
            try:
                incoming_message = websocket_connection.recv(
                    timeout=self._response_poll_timeout_seconds
                )
            except TimeoutError:
                continue
            except ConnectionClosed:
                return
            try:
                self._handle_incoming_message(
                    incoming_message=incoming_message,
                    websocket_connection=websocket_connection,
                    remote_address=remote_address,
                )
            except UnicodeDecodeError:
                self._safe_log(
                    "debug",
                    message=(
                        "UsbWebSocketTransportAdapter/_run_websocket_session: "
                        "ignored non-UTF8 websocket frame from mobile runtime."
                    ),
                )

    def _perform_auth_challenge(
        self,
        *,
        websocket_connection: UsbWebSocketConnection,
        config: UsbBootstrapConfig,
    ) -> None:
        challenge_rand = secrets.token_hex(16)
        websocket_connection.send(
            json.dumps(
                {
                    "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                    "operation": USB_AUTH_CHALLENGE_OPERATION,
                    "request_id": USB_AUTH_CHALLENGE_REQUEST_ID,
                    "body_schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
                    "body": {
                        "schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
                        "sid": config.session_id,
                        "rand": challenge_rand,
                    },
                },
                separators=(",", ":"),
                sort_keys=True,
            )
        )

        challenge_deadline = time.monotonic() + USB_AUTH_CHALLENGE_TIMEOUT_SECONDS
        while not self._stop_event.is_set() and time.monotonic() < challenge_deadline:
            remaining_timeout = challenge_deadline - time.monotonic()
            recv_timeout = min(self._response_poll_timeout_seconds, max(remaining_timeout, 0.01))
            try:
                incoming_message = websocket_connection.recv(timeout=recv_timeout)
            except TimeoutError:
                continue
            except ConnectionClosed as exc:
                raise RuntimeError("Desktop USB auth challenge connection closed.") from exc

            if isinstance(incoming_message, bytes):
                continue

            try:
                challenge_response = json.loads(incoming_message)
            except json.JSONDecodeError:
                continue
            if not isinstance(challenge_response, dict):
                continue
            if challenge_response.get("schema") != MOBILE_TRANSPORT_ENVELOPE_SCHEMA:
                continue
            if challenge_response.get("request_id") != USB_AUTH_CHALLENGE_REQUEST_ID:
                continue

            status_code = challenge_response.get("status_code")
            if not isinstance(status_code, int):
                raise RuntimeError("Desktop USB auth challenge returned an invalid status code.")
            response_body = challenge_response.get("body")
            if not isinstance(response_body, dict):
                raise RuntimeError("Desktop USB auth challenge returned an invalid response body.")
            if not (200 <= status_code < 300):
                rejection_message = response_body.get("message")
                if isinstance(rejection_message, str) and rejection_message.strip():
                    raise RuntimeError(
                        "Desktop USB auth challenge was rejected by mobile runtime: "
                        f"{rejection_message.strip()}"
                    )
                raise RuntimeError("Desktop USB auth challenge was rejected by mobile runtime.")

            challenge_proof = response_body.get("proof")
            if not isinstance(challenge_proof, str) or not challenge_proof.strip():
                raise RuntimeError("Desktop USB auth challenge response did not include a proof digest.")
            if not self.verify_auth_digest(
                rand=challenge_rand,
                provided_digest=challenge_proof.strip(),
            ):
                raise RuntimeError("Desktop USB auth challenge proof digest verification failed.")
            return

        if self._stop_event.is_set():
            raise RuntimeError("Desktop stopped while waiting for USB auth challenge response.")
        raise RuntimeError("Desktop USB auth challenge timed out.")

    def _handle_incoming_message(
        self,
        *,
        incoming_message: str | bytes,
        websocket_connection: UsbWebSocketConnection,
        remote_address: str,
    ) -> None:
        if isinstance(incoming_message, bytes):
            self._append_pending_asset_chunk(incoming_message)
            return

        raw_message = incoming_message

        request_id, response = self._dispatch_envelope_request(
            raw_message,
            remote_address=remote_address,
        )
        if response is None:
            return
        if request_id is None:
            self._safe_log(
                "warning",
                message=(
                    "UsbWebSocketTransportAdapter/_handle_incoming_message: "
                    "skipping USB response because request_id is missing."
                ),
            )
            return

        websocket_connection.send(
            self._encode_response_envelope(
                request_id=request_id,
                response=response,
            )
        )

    def _dispatch_envelope_request(
        self,
        raw_message: str,
        *,
        remote_address: str | None,
    ) -> tuple[str | None, MobileTransportResponse | None]:
        parsed_envelope = self._parse_envelope(raw_message)
        if isinstance(parsed_envelope, MobileTransportResponse):
            return self._extract_request_id(raw_message), parsed_envelope

        operation = parsed_envelope["operation"]
        request_id = parsed_envelope.get("request_id")
        if not isinstance(request_id, str) or not request_id.strip():
            return None, self._transport_error_response(
                message="Desktop rejected a USB transport message with a missing request id.",
            )
        request_id = request_id.strip()

        if operation == TRANSFER_ASSET_OPERATION:
            payload_or_error = self._dispatch_transfer_asset_stream_payload(
                request_id=request_id,
                raw_body=parsed_envelope.get("body"),
            )
            if payload_or_error is None:
                return request_id, None
            if isinstance(payload_or_error, MobileTransportResponse):
                return request_id, payload_or_error
        else:
            raw_body = parsed_envelope.get("body")
            if raw_body is None:
                payload_or_error = {}
            elif isinstance(raw_body, dict):
                payload_or_error = raw_body
            else:
                return request_id, self._transport_error_response(
                    message=(
                        "Desktop requires JSON object payloads for "
                        f"USB transport operation '{operation}'."
                    ),
                )

        context = MobileTransportContext(
            transport=MobileTransportKind.USB_WEBSOCKET,
            operation=operation,
            request_id=request_id,
            remote_address=remote_address,
        )

        try:
            response = self._router.dispatch(
                operation=operation,
                payload=payload_or_error,
                context=context,
            )
        except MobileTransportRouteNotFoundError:
            response = self._transport_error_response(
                message=f"Desktop does not support USB transport operation '{operation}'.",
            )
        finally:
            if (
                operation == TRANSFER_ASSET_OPERATION
                and isinstance(payload_or_error, TransferAssetUploadPayload)
                and payload_or_error.body_stream is not None
            ):
                payload_or_error.body_stream.close()
        return request_id, response

    def _dispatch_transfer_asset_stream_payload(
        self,
        *,
        request_id: str,
        raw_body: object,
    ) -> TransferAssetUploadPayload | MobileTransportResponse | None:
        if not isinstance(raw_body, dict):
            return self._transport_error_response(
                message="Desktop requires JSON object payloads for transfer asset requests.",
            )

        stream_state = raw_body.get(TRANSFER_ASSET_STREAM_STATE_FIELD)
        if stream_state == TRANSFER_ASSET_STREAM_STATE_START:
            metadata_payload = dict(raw_body)
            metadata_payload.pop(TRANSFER_ASSET_STREAM_STATE_FIELD, None)
            metadata_payload.pop("chunk_size", None)
            self._start_pending_asset_upload(
                request_id=request_id,
                metadata_payload=metadata_payload,
            )
            return None
        if stream_state == TRANSFER_ASSET_STREAM_STATE_COMPLETE:
            return self._complete_pending_asset_upload(request_id=request_id)

        return self._transport_error_response(
            message=(
                "Desktop rejected transfer asset stream message with an unsupported "
                f"'{TRANSFER_ASSET_STREAM_STATE_FIELD}' value."
            )
        )

    def _start_pending_asset_upload(
        self,
        *,
        request_id: str,
        metadata_payload: dict[str, object],
    ) -> None:
        with self._lock:
            self._asset_upload_stream.start(
                request_id=request_id,
                metadata_payload=metadata_payload,
            )

    def _append_pending_asset_chunk(self, chunk: bytes) -> None:
        append_error: str | None = None
        with self._lock:
            append_error = self._asset_upload_stream.append_chunk(chunk=chunk)
            active_request_id = self._asset_upload_stream.active_request_id
        if append_error is None:
            return
        if not chunk:
            return
        if len(chunk) > TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES:
            raise RuntimeError(append_error)
        if active_request_id is None:
            self._safe_log(
                "warning",
                message=(
                    "UsbWebSocketTransportAdapter/_append_pending_asset_chunk: "
                    "ignoring binary frame without a matching transfer asset start envelope."
                ),
            )
            return
        raise RuntimeError(append_error)

    def _complete_pending_asset_upload(
        self,
        *,
        request_id: str,
    ) -> TransferAssetUploadPayload | MobileTransportResponse:
        with self._lock:
            payload_or_error = self._asset_upload_stream.complete(request_id=request_id)
        if isinstance(payload_or_error, str):
            return self._transport_error_response(
                message=payload_or_error,
            )
        return payload_or_error

    def _encode_response_envelope(
        self,
        *,
        request_id: str,
        response: MobileTransportResponse,
    ) -> str:
        return json.dumps(
            {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "request_id": request_id,
                "status_code": response.status_code,
                "body": response.payload,
            },
            separators=(",", ":"),
            sort_keys=True,
        )

    def _extract_request_id(self, raw_message: str) -> str | None:
        try:
            parsed_value = json.loads(raw_message)
        except json.JSONDecodeError:
            return None
        if not isinstance(parsed_value, dict):
            return None
        request_id = parsed_value.get("request_id")
        if not isinstance(request_id, str) or not request_id.strip():
            return None
        return request_id.strip()

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
                "status": USB_TRANSPORT_REJECTED_STATUS,
                "message": message,
            },
        )

    def _require_bootstrap_config(self) -> UsbBootstrapConfig:
        with self._lock:
            if self._bootstrap_config is None:
                raise RuntimeError("USB bootstrap config is not available.")
            return self._bootstrap_config

    def _probe_usb_tunnel(
        self,
        config: UsbBootstrapConfig,
    ) -> UsbTunnelTarget | None:
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
            self._set_probe_error(None)
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

            self._set_probe_error(None)
            self._safe_log(
                "info",
                message=(
                    "UsbWebSocketTransportAdapter/_probe_usb_tunnel: found USB tunnel candidate "
                    f"device={connected_target.device_udid} port={connected_target.remote_port}"
                ),
            )
            return connected_target

        self._set_probe_error("Desktop could not connect to any USB bootstrap port candidates.")
        return None

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

    def _set_probe_error(self, message: str | None) -> None:
        with self._lock:
            self._last_probe_error = message

    def _set_ready_state(self) -> None:
        with self._lock:
            if self._state != UsbTransportState.STOPPED:
                self._state = UsbTransportState.READY
            self._active_tunnel_target = None
            self._close_active_connection_locked()

    def _wait_for_retry_interval(self) -> None:
        self._stop_event.wait(timeout=self._probe_interval_seconds)

    def _close_active_connection_locked(self) -> None:
        websocket_connection = self._active_websocket_connection
        tunnel_socket = self._active_tunnel_socket
        self._active_websocket_connection = None
        self._active_tunnel_socket = None
        self._asset_upload_stream.clear()

        if websocket_connection is not None:
            try:
                websocket_connection.close()
            except (OSError, RuntimeError, WebSocketException):
                pass

        if tunnel_socket is not None:
            try:
                tunnel_socket.close()
            except OSError:
                pass


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
