from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import errno
import json
import secrets
import socket
import threading
from urllib.parse import parse_qs, urlparse

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_discovery import discover_advertised_hosts
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePairingToken, MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import (
    derive_pairing_key_b64,
    get_or_create_desktop_device_id,
    get_or_create_mobile_folder,
    insert_mobile_backup_session,
    upsert_mobile_device,
)
from dt_image_search.mobile.mobile_transfer_service import (
    MOBILE_TRANSFER_ASSET_PATH,
    MOBILE_TRANSFER_COMPLETE_PATH,
    MOBILE_TRANSFER_EXISTENCE_PATH,
    MOBILE_TRANSFER_START_PATH,
    MobileTransferService,
    decode_transfer_asset_metadata,
)
from dt_image_search.model.dts_db import create_db_conn

PAIRING_PROTOCOL_SCHEMA = "dtis.mobile-pairing.v1"
PAIRING_CLAIM_PATH = "/api/mobile/pairing/claim"
PAIRING_TRANSPORT = "lan"


class PairingResultState(str, Enum):
    WAITING = "waiting"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    EXPIRED = "expired"


@dataclass(frozen=True)
class MobilePairingResult:
    state: PairingResultState
    message: str
    device_name: str | None = None
    device_uuid: str | None = None
    folder_path: str | None = None
    session_id: str | None = None
    transport: str | None = None


class _MobilePairingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True


class MobilePairingService:
    def __init__(
        self,
        ctx: BMContext,
        *,
        listen_host: str = "0.0.0.0",
        advertised_host: str | None = None,
        desktop_name: str | None = None,
    ):
        self._ctx = ctx
        self._listen_host = listen_host
        self._advertised_host = advertised_host
        self._desktop_name = desktop_name or socket.gethostname()
        self._lock = threading.RLock()
        self._server: _MobilePairingHTTPServer | None = None
        self._server_thread: threading.Thread | None = None
        self._endpoint_url: str | None = None
        self._endpoint_urls: tuple[str, ...] = tuple()
        self._active_session: MobilePairingSessionDraft | None = None
        self._transfer_service = MobileTransferService(ctx)
        self._pairing_result = MobilePairingResult(
            state=PairingResultState.WAITING,
            message="Scan the QR code from the mobile app to begin pairing.",
        )

    @property
    def endpoint_url(self) -> str:
        self._ensure_server_started()
        if self._endpoint_url is None:
            raise RuntimeError("Pairing endpoint URL is not available.")
        return self._endpoint_url

    @property
    def endpoint_urls(self) -> tuple[str, ...]:
        self._ensure_server_started()
        if not self._endpoint_urls:
            raise RuntimeError("Pairing endpoint URLs are not available.")
        return self._endpoint_urls

    def start_pairing_session(
        self,
        destination_parent: str,
        now: datetime | None = None,
    ) -> MobilePairingSessionDraft:
        self._ensure_server_started()
        with self._lock:
            self._active_session = MobilePairingSessionDraft.create(
                destination_parent=destination_parent,
                desktop_endpoint_urls=self.endpoint_urls,
                now=now,
            )
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.WAITING,
                message="Waiting for the mobile app to claim this pairing session.",
                session_id=self._active_session.session_id,
            )
            _log(
                "info",
                message=(
                    "MobilePairingService/start_pairing_session: created pairing session "
                    f"{self._active_session.session_id} on {self.endpoint_url}"
                ),
            )
            return self._active_session

    def refresh_token(self, platform: MobilePlatform, now: datetime | None = None) -> MobilePairingToken:
        with self._lock:
            if self._active_session is None:
                raise RuntimeError("No active pairing session is available.")
            if self._pairing_result.state == PairingResultState.ACCEPTED:
                raise RuntimeError("Cannot refresh QR tokens after pairing is already accepted.")
            return self._active_session.refresh_token(platform, now=now)

    def current_result(self) -> MobilePairingResult:
        with self._lock:
            return self._pairing_result

    def close_active_session(self) -> None:
        with self._lock:
            self._active_session = None
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.WAITING,
                message="Scan the QR code from the mobile app to begin pairing.",
            )

    def shutdown(self) -> None:
        server_to_stop: _MobilePairingHTTPServer | None
        with self._lock:
            server_to_stop = self._server
            self._server = None
            self._server_thread = None
            self._endpoint_url = None
            self._endpoint_urls = tuple()
            self._active_session = None

        if server_to_stop is not None:
            server_to_stop.shutdown()
            server_to_stop.server_close()

    def handle_pairing_request(
        self,
        request_payload: dict[str, str],
        *,
        now: datetime | None = None,
    ) -> tuple[int, dict[str, object]]:
        current_time = _utc_now(now)
        with self._lock:
            active_session = self._active_session
            if active_session is None:
                return _response(status_code=404, state=PairingResultState.REJECTED, message="There is no active desktop pairing session.")

            if self._pairing_result.state == PairingResultState.ACCEPTED:
                return _response(status_code=409, state=PairingResultState.REJECTED, message="This pairing session was already accepted.")

            required_fields = ("schema", "sid", "opt", "platform", "device_uuid", "device_name", "client_nonce")
            for field_name in required_fields:
                field_value = request_payload.get(field_name)
                if not isinstance(field_value, str) or not field_value.strip():
                    return _response(
                        status_code=400,
                        state=PairingResultState.REJECTED,
                        message=f"The pairing request is missing the required field '{field_name}'.",
                    )

            if request_payload["schema"] != PAIRING_PROTOCOL_SCHEMA:
                return _response(status_code=400, state=PairingResultState.REJECTED, message="The pairing request schema version is unsupported.")

            if request_payload["sid"] != active_session.session_id:
                return _response(status_code=404, state=PairingResultState.REJECTED, message="The pairing request does not match the active desktop session.")

            try:
                requested_platform = MobilePlatform(request_payload["platform"])
            except ValueError:
                return _response(status_code=400, state=PairingResultState.REJECTED, message="The pairing request platform is unsupported.")

            token = active_session.token_for(requested_platform)

            if token.is_expired(current_time):
                self._pairing_result = MobilePairingResult(
                    state=PairingResultState.EXPIRED,
                    message="The desktop pairing code expired before the mobile app completed pairing.",
                    session_id=active_session.session_id,
                )
                return _response(status_code=410, state=PairingResultState.EXPIRED, message="This pairing code expired. Refresh it on desktop and scan again.")

            if request_payload["opt"] != token.one_time_passcode:
                return _response(status_code=403, state=PairingResultState.REJECTED, message="The pairing code was rejected by desktop.")

            device_uuid = request_payload["device_uuid"].strip()
            device_name = request_payload["device_name"].strip()
            client_nonce = request_payload["client_nonce"].strip()
            server_nonce = secrets.token_urlsafe(24)

            with create_db_conn(ctx=self._ctx) as conn:
                desktop_device_id = get_or_create_desktop_device_id(conn)
                trust_key_b64 = derive_pairing_key_b64(
                    session_id=active_session.session_id,
                    one_time_passcode=token.one_time_passcode,
                    device_uuid=device_uuid,
                    platform=requested_platform.value,
                    client_nonce=client_nonce,
                    server_nonce=server_nonce,
                    desktop_device_id=desktop_device_id,
                )
                upsert_mobile_device(
                    conn,
                    device_uuid=device_uuid,
                    platform=requested_platform.value,
                    device_name=device_name,
                    trust_key_b64=trust_key_b64,
                    paired_at=current_time,
                )
                folder_record = get_or_create_mobile_folder(
                    conn,
                    destination_parent=active_session.destination_parent,
                    device_uuid=device_uuid,
                    device_name=device_name,
                    updated_at=current_time,
                )
                insert_mobile_backup_session(
                    conn,
                    session_id=active_session.session_id,
                    device_uuid=device_uuid,
                    folder_id=folder_record.folder_id,
                    status="paired",
                    started_at=active_session.created_at,
                    paired_at=current_time,
                )

            acceptance_message = f"Pairing accepted for {device_name}. Desktop is ready for LAN transfer."
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.ACCEPTED,
                message=acceptance_message,
                device_name=device_name,
                device_uuid=device_uuid,
                folder_path=folder_record.folder_path,
                session_id=active_session.session_id,
                transport=PAIRING_TRANSPORT,
            )
            _log(
                "info",
                message=(
                    "MobilePairingService/handle_pairing_request: accepted pairing session "
                    f"{active_session.session_id} for {requested_platform.value} device {device_uuid}"
                ),
            )
            return (
                200,
                {
                    "schema": PAIRING_PROTOCOL_SCHEMA,
                    "status": PairingResultState.ACCEPTED.value,
                    "message": acceptance_message,
                    "session_id": active_session.session_id,
                    "desktop_device_id": desktop_device_id,
                    "desktop_name": self._desktop_name,
                    "device_uuid": device_uuid,
                    "folder_id": folder_record.folder_id,
                    "folder_path": folder_record.folder_path,
                    "transport": PAIRING_TRANSPORT,
                    "paired_at": current_time.isoformat(timespec="seconds"),
                    "server_nonce": server_nonce,
                },
            )

    def _ensure_server_started(self) -> None:
        with self._lock:
            if self._server is not None:
                return

            handler_class = _build_handler(self)
            self._server = _MobilePairingHTTPServer((self._listen_host, 0), handler_class)
            port = self._server.server_address[1]
            advertised_hosts = _resolve_advertised_hosts(self._advertised_host)
            self._endpoint_urls = tuple(_format_pairing_endpoint_url(host, port) for host in advertised_hosts)
            self._endpoint_url = self._endpoint_urls[0]
            self._server_thread = threading.Thread(
                target=self._server.serve_forever,
                name="mobile-pairing-bootstrap",
                daemon=True,
            )
            self._server_thread.start()
            _log(
                "info",
                message=(
                    "MobilePairingService/_ensure_server_started: listening for pairing requests on "
                    f"{self._endpoint_url}"
                ),
            )


def _build_handler(service: MobilePairingService) -> type[BaseHTTPRequestHandler]:
    class PairingHandler(BaseHTTPRequestHandler):
        def handle_one_request(self) -> None:
            try:
                super().handle_one_request()
            except OSError as exc:
                if not _is_ignorable_socket_disconnect(exc):
                    raise
                self.close_connection = True
                _try_log(
                    "debug",
                    message=(
                        "MobilePairingService/http: ignoring disconnected client during HTTP request handling "
                        f"from {self.client_address}: {exc}"
                    ),
                )

        def do_POST(self) -> None:
            try:
                parsed_path = urlparse(self.path)
                if parsed_path.path == PAIRING_CLAIM_PATH:
                    request_payload = self._read_json_payload(
                        schema=PAIRING_PROTOCOL_SCHEMA,
                        status=PairingResultState.REJECTED.value,
                        parse_error_message="Desktop could not parse the pairing request JSON payload.",
                        object_error_message="Desktop requires JSON object payloads for pairing requests.",
                    )
                    if request_payload is None:
                        return

                    status_code, response_payload = service.handle_pairing_request(request_payload)
                    self._write_json_response(status_code, response_payload)
                    return

                if parsed_path.path == MOBILE_TRANSFER_START_PATH:
                    request_payload = self._read_json_payload(
                        schema="dtis.mobile-transfer.v1",
                        status="rejected",
                        parse_error_message="Desktop could not parse the transfer request JSON payload.",
                        object_error_message="Desktop requires JSON object payloads for transfer requests.",
                    )
                    if request_payload is None:
                        return

                    status_code, response_payload = service._transfer_service.handle_start_request(request_payload)
                    self._write_json_response(status_code, response_payload)
                    return

                if parsed_path.path == MOBILE_TRANSFER_EXISTENCE_PATH:
                    request_payload = self._read_json_payload(
                        schema="dtis.mobile-transfer.v1",
                        status="rejected",
                        parse_error_message="Desktop could not parse the transfer existence JSON payload.",
                        object_error_message="Desktop requires JSON object payloads for transfer existence requests.",
                    )
                    if request_payload is None:
                        return

                    status_code, response_payload = service._transfer_service.handle_asset_existence_request(request_payload)
                    self._write_json_response(status_code, response_payload)
                    return

                if parsed_path.path == MOBILE_TRANSFER_COMPLETE_PATH:
                    request_payload = self._read_json_payload(
                        schema="dtis.mobile-transfer.v1",
                        status="rejected",
                        parse_error_message="Desktop could not parse the transfer completion JSON payload.",
                        object_error_message="Desktop requires JSON object payloads for transfer completion requests.",
                    )
                    if request_payload is None:
                        return

                    status_code, response_payload = service._transfer_service.handle_complete_request(request_payload)
                    self._write_json_response(status_code, response_payload)
                    return

                if parsed_path.path == MOBILE_TRANSFER_ASSET_PATH:
                    query_parameters = parse_qs(parsed_path.query, keep_blank_values=False)
                    encoded_metadata = query_parameters.get("meta", [None])[0]
                    if not encoded_metadata:
                        self._write_json_response(
                            400,
                            {
                                "schema": "dtis.mobile-transfer.v1",
                                "status": "rejected",
                                "message": "Desktop did not receive the transfer asset metadata.",
                            },
                        )
                        return
                    try:
                        metadata_payload = decode_transfer_asset_metadata(encoded_metadata)
                    except (OSError, ValueError, json.JSONDecodeError):
                        self._write_json_response(
                            400,
                            {
                                "schema": "dtis.mobile-transfer.v1",
                                "status": "rejected",
                                "message": "Desktop could not parse the transfer asset metadata.",
                            },
                        )
                        return

                    content_length = int(self.headers.get("Content-Length", "0"))
                    status_code, response_payload = service._transfer_service.handle_asset_upload(
                        metadata_payload=metadata_payload,
                        body_stream=self.rfile,
                        content_length=content_length,
                    )
                    self._write_json_response(status_code, response_payload)
                    return

                if parsed_path.path != PAIRING_CLAIM_PATH:
                    self._write_json_response(404, {"schema": PAIRING_PROTOCOL_SCHEMA, "status": PairingResultState.REJECTED.value, "message": "Unknown pairing endpoint."})
                    return
            except Exception as exc:
                _try_log(
                    "error",
                    error_type=type(exc).__name__,
                    where="mobile_pairing_service.PairingHandler.do_POST",
                    message=f"Unhandled pairing request error: {exc}",
                )
                if not self.wfile.closed:
                    self._write_json_response(
                        500,
                        {
                            "schema": PAIRING_PROTOCOL_SCHEMA,
                            "status": PairingResultState.REJECTED.value,
                            "message": "Desktop failed while processing the pairing request. Retry pairing and check desktop logs if the issue persists.",
                        },
                    )

        def log_message(self, format: str, *args: object) -> None:
            _try_log("debug", message=f"MobilePairingService/http: {format % args}")

        def _read_json_payload(
            self,
            *,
            schema: str,
            status: str,
            parse_error_message: str,
            object_error_message: str,
        ) -> dict[str, object] | None:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_payload = self.rfile.read(content_length)
            try:
                request_payload = json.loads(raw_payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._write_json_response(
                    400,
                    {
                        "schema": schema,
                        "status": status,
                        "message": parse_error_message,
                    },
                )
                return None

            if not isinstance(request_payload, dict):
                self._write_json_response(
                    400,
                    {
                        "schema": schema,
                        "status": status,
                        "message": object_error_message,
                    },
                )
                return None
            return request_payload

        def _write_json_response(self, status_code: int, payload: dict[str, object]) -> None:
            encoded_body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
            self.close_connection = True
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Connection", "close")
            self.send_header("Content-Length", str(len(encoded_body)))
            self.end_headers()
            self.wfile.write(encoded_body)

    return PairingHandler
def _response(
    *,
    status_code: int,
    state: PairingResultState,
    message: str,
) -> tuple[int, dict[str, object]]:
    return (
        status_code,
        {
            "schema": PAIRING_PROTOCOL_SCHEMA,
            "status": state.value,
            "message": message,
        },
    )


def _resolve_advertised_hosts(configured_host: str | None) -> tuple[str, ...]:
    if configured_host:
        return (configured_host,)
    return discover_advertised_hosts()


def _format_pairing_endpoint_url(host: str, port: int) -> str:
    formatted_host = host
    if ":" in formatted_host and not formatted_host.startswith("["):
        formatted_host = f"[{formatted_host}]"
    return f"http://{formatted_host}:{port}{PAIRING_CLAIM_PATH}"


def _is_ignorable_socket_disconnect(exc: BaseException) -> bool:
    if isinstance(exc, (BrokenPipeError, ConnectionResetError)):
        return True
    return isinstance(exc, OSError) and exc.errno in {
        errno.EPIPE,
        errno.ECONNABORTED,
        errno.ECONNRESET,
        errno.ENOTCONN,
    }


def _try_log(severity: str, *, message: str, error_type: str = "", where: str = "") -> None:
    try:
        _log(severity, message=message, error_type=error_type, where=where)
    except Exception:
        # Pairing HTTP request handling must not fail just because telemetry logging failed.
        return


def _utc_now(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _log(level: str, error_type: str = "", message: str = "", where: str = ""):
    from dt_image_search.telemetry.telemetry_client import log

    log(severity=level, error_type=error_type, where=where, message=message)
