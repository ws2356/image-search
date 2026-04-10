from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import secrets
import socket
import threading
from urllib.parse import urlparse

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePairingToken, MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import (
    derive_pairing_key_b64,
    get_or_create_desktop_device_id,
    get_or_create_mobile_folder,
    insert_mobile_backup_session,
    upsert_mobile_device,
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
        self._advertised_host = advertised_host or _discover_advertised_host()
        self._desktop_name = desktop_name or socket.gethostname()
        self._lock = threading.RLock()
        self._server: _MobilePairingHTTPServer | None = None
        self._server_thread: threading.Thread | None = None
        self._endpoint_url: str | None = None
        self._active_session: MobilePairingSessionDraft | None = None
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

    def start_pairing_session(
        self,
        destination_parent: str,
        now: datetime | None = None,
    ) -> MobilePairingSessionDraft:
        self._ensure_server_started()
        with self._lock:
            self._active_session = MobilePairingSessionDraft.create(
                destination_parent=destination_parent,
                desktop_endpoint_url=self.endpoint_url,
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
                    "paired_at": current_time.isoformat(),
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
            self._endpoint_url = f"http://{self._advertised_host}:{port}{PAIRING_CLAIM_PATH}"
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
        def do_POST(self) -> None:
            parsed_path = urlparse(self.path)
            if parsed_path.path != PAIRING_CLAIM_PATH:
                self._write_json_response(404, {"schema": PAIRING_PROTOCOL_SCHEMA, "status": PairingResultState.REJECTED.value, "message": "Unknown pairing endpoint."})
                return

            content_length = int(self.headers.get("Content-Length", "0"))
            raw_payload = self.rfile.read(content_length)
            try:
                request_payload = json.loads(raw_payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._write_json_response(
                    400,
                    {
                        "schema": PAIRING_PROTOCOL_SCHEMA,
                        "status": PairingResultState.REJECTED.value,
                        "message": "Desktop could not parse the pairing request JSON payload.",
                    },
                )
                return

            status_code, response_payload = service.handle_pairing_request(request_payload)
            self._write_json_response(status_code, response_payload)

        def log_message(self, format: str, *args: object) -> None:
            _log("debug", message=f"MobilePairingService/http: {format % args}")

        def _write_json_response(self, status_code: int, payload: dict[str, object]) -> None:
            encoded_body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json")
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


def _discover_advertised_host() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe_socket:
            probe_socket.connect(("8.8.8.8", 80))
            advertised_host = probe_socket.getsockname()[0]
            if advertised_host:
                return advertised_host
    except OSError:
        pass
    return "127.0.0.1"


def _utc_now(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _log(level: str, *, message: str) -> None:
    from dt_image_search.telemetry.telemetry_client import log

    log(level, message=message)
