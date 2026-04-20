from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
import secrets
import socket
import threading

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_discovery import discover_advertised_hosts
from dt_image_search.mobile.mobile_pairing_session import (
    MobilePairingSessionDraft,
    MobilePairingToken,
    MobilePlatform,
)
from dt_image_search.mobile.mobile_pairing_store import (
    derive_pairing_key_b64,
    get_or_create_desktop_device_id,
    get_or_create_mobile_folder,
    insert_mobile_backup_session,
    upsert_mobile_device,
)
from dt_image_search.mobile.mobile_capability_exchange_service import (
    MOBILE_CAPABILITY_EXCHANGE_PATH,
    MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
    MobileCapabilityExchangeService,
)
from dt_image_search.mobile.mobile_transfer_service import (
    MOBILE_TRANSFER_ASSET_PATH,
    MOBILE_TRANSFER_COMPLETE_PATH,
    MOBILE_TRANSFER_EXISTENCE_PATH,
    MOBILE_TRANSFER_SCHEMA,
    MOBILE_TRANSFER_START_PATH,
    MobileTransferService,
)
from dt_image_search.mobile.mobile_update_prompt_service import (
    MOBILE_UPDATE_PROMPT_PATH,
    MOBILE_UPDATE_PROMPT_SCHEMA,
    MobileUpdatePromptService,
)
from dt_image_search.mobile.transport.contracts import (
    CAPABILITY_EXCHANGE_OPERATION,
    PAIRING_CLAIM_OPERATION,
    TRANSFER_ASSET_OPERATION,
    TRANSFER_COMPLETE_OPERATION,
    TRANSFER_EXISTENCE_OPERATION,
    TRANSFER_START_OPERATION,
    UPDATE_PROMPT_OPERATION,
    MobileTransportKind,
    MobileTransportRequest,
    MobileTransportResponse,
    TransferAssetUploadPayload,
)
from dt_image_search.mobile.transport.lan_http_adapter import (
    LanHttpTransportAdapter,
    is_ignorable_socket_disconnect as _transport_is_ignorable_socket_disconnect,
)
from dt_image_search.mobile.transport.router import MobileTransportRouter
from dt_image_search.mobile.transport.transport_manager import MobileTransportManager
from dt_image_search.mobile.transport.usb_ws_adapter import (
    UsbBootstrapConfig,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
)
from dt_image_search.build_flavor import get_build_type
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.tools.dts_event_bus import default_bus

PAIRING_PROTOCOL_SCHEMA = "dtis.mobile-pairing.v1"
PAIRING_CLAIM_PATH = "/api/mobile/pairing/claim"
PAIRING_TRANSPORT_LAN = "lan"
PAIRING_TRANSPORT_USB = "usb"
MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT = "mobile_app_foreground_state_changed"


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
        base_desktop_name = desktop_name or socket.gethostname()
        self._desktop_name = _desktop_name_for_build(base_desktop_name, get_build_type())
        self._lock = threading.RLock()
        self._endpoint_url: str | None = None
        self._endpoint_urls: tuple[str, ...] = tuple()
        self._active_session: MobilePairingSessionDraft | None = None
        self._transfer_service = MobileTransferService(ctx)
        self._capability_exchange_service = MobileCapabilityExchangeService(ctx)
        self._update_prompt_service = MobileUpdatePromptService(ctx)
        self._pairing_result = MobilePairingResult(
            state=PairingResultState.WAITING,
            message="Scan the QR code from the mobile app to begin pairing.",
        )
        self._transfer_transport_by_session_id: dict[str, MobileTransportKind] = {}
        self._app_is_foreground = True
        self._app_foreground_state_subscription = default_bus.subscribe(
            MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT,
            self._on_app_foreground_state_changed,
        )

        self._transport_router = MobileTransportRouter()
        self._register_transport_routes()
        self._transport_manager = self._build_transport_manager()

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
            active_session = self._active_session
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.WAITING,
                message="Waiting for the mobile app to claim this pairing session.",
                session_id=active_session.session_id,
            )
        self._configure_usb_bootstrap_for_session(active_session)
        _log(
            "info",
            message=(
                "MobilePairingService/start_pairing_session: created pairing session "
                f"{active_session.session_id} on {self.endpoint_url}"
            ),
        )
        return active_session

    def refresh_token(self, platform: MobilePlatform, now: datetime | None = None) -> MobilePairingToken:
        with self._lock:
            if self._active_session is None:
                raise RuntimeError("No active pairing session is available.")
            if self._pairing_result.state == PairingResultState.ACCEPTED:
                raise RuntimeError("Cannot refresh QR tokens after pairing is already accepted.")
            refreshed_token = self._active_session.refresh_token(platform, now=now)
            session_id = self._active_session.session_id
        if platform == MobilePlatform.IOS:
            self._configure_usb_bootstrap_for_token(
                session_id=session_id,
                token=refreshed_token,
            )
        return refreshed_token

    def current_result(self) -> MobilePairingResult:
        with self._lock:
            return self._pairing_result

    def close_active_session(self) -> None:
        with self._lock:
            closing_session = self._active_session
            should_stop_usb = self._pairing_result.state != PairingResultState.ACCEPTED
            self._active_session = None
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.WAITING,
                message="Scan the QR code from the mobile app to begin pairing.",
            )
        if closing_session is not None:
            self._clear_transfer_transport_tracking(closing_session.session_id)
        if should_stop_usb:
            self._transport_manager.stop_usb()

    def shutdown(self) -> None:
        app_foreground_state_subscription = None
        with self._lock:
            self._endpoint_url = None
            self._endpoint_urls = tuple()
            self._active_session = None
            self._transfer_transport_by_session_id.clear()
            app_foreground_state_subscription = self._app_foreground_state_subscription
            self._app_foreground_state_subscription = None

        self._transport_manager.stop_all()
        if app_foreground_state_subscription is not None:
            app_foreground_state_subscription.dispose()

    def handle_pairing_request(
        self,
        request_payload: dict[str, object],
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
                return _response(
                    status_code=400,
                    state=PairingResultState.REJECTED,
                    message="The pairing request schema version is unsupported.",
                )

            if request_payload["sid"] != active_session.session_id:
                return _response(
                    status_code=404,
                    state=PairingResultState.REJECTED,
                    message="The pairing request does not match the active desktop session.",
                )

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

            selected_transport = self._resolve_pairing_transport(requested_platform)
            if selected_transport == PAIRING_TRANSPORT_USB:
                acceptance_message = f"Pairing accepted for {device_name}. Desktop is ready for USB transfer."
            else:
                acceptance_message = f"Pairing accepted for {device_name}. Desktop is ready for LAN transfer."
            self._pairing_result = MobilePairingResult(
                state=PairingResultState.ACCEPTED,
                message=acceptance_message,
                device_name=device_name,
                device_uuid=device_uuid,
                folder_path=folder_record.folder_path,
                session_id=active_session.session_id,
                transport=selected_transport,
            )
            _log(
                "info",
                message=(
                    "MobilePairingService/handle_pairing_request: accepted pairing session "
                    f"{active_session.session_id} for {requested_platform.value} device {device_uuid} "
                    f"transport={selected_transport}"
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
                    "transport": selected_transport,
                    "paired_at": current_time.isoformat(timespec="seconds"),
                    "server_nonce": server_nonce,
                },
            )

    def _register_transport_routes(self) -> None:
        self._transport_router.register(PAIRING_CLAIM_OPERATION, self._dispatch_pairing_claim_operation)
        self._transport_router.register(CAPABILITY_EXCHANGE_OPERATION, self._dispatch_capability_exchange_operation)
        self._transport_router.register(UPDATE_PROMPT_OPERATION, self._dispatch_update_prompt_operation)
        self._transport_router.register(TRANSFER_START_OPERATION, self._dispatch_transfer_start_operation)
        self._transport_router.register(TRANSFER_EXISTENCE_OPERATION, self._dispatch_transfer_existence_operation)
        self._transport_router.register(TRANSFER_ASSET_OPERATION, self._dispatch_transfer_asset_operation)
        self._transport_router.register(TRANSFER_COMPLETE_OPERATION, self._dispatch_transfer_complete_operation)

    def _dispatch_pairing_claim_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return MobileTransportResponse(
                status_code=400,
                payload={
                    "schema": PAIRING_PROTOCOL_SCHEMA,
                    "status": PairingResultState.REJECTED.value,
                    "message": "Desktop requires JSON object payloads for pairing requests.",
                },
            )
        status_code, response_payload = self.handle_pairing_request(request.payload)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_transfer_start_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return _transfer_object_payload_error(
                message="Desktop requires JSON object payloads for transfer requests.",
            )
        self._track_transfer_transport(request=request, payload=request.payload)
        status_code, response_payload = self._transfer_service.handle_start_request(request.payload)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_capability_exchange_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return _capability_exchange_object_payload_error(
                message="Desktop requires JSON object payloads for capability exchange requests.",
            )
        status_code, response_payload = self._capability_exchange_service.handle_exchange_request(request.payload)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_update_prompt_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return _update_prompt_object_payload_error(
                message="Desktop requires JSON object payloads for update prompt requests.",
            )
        status_code, response_payload = self._update_prompt_service.handle_prompt_request(request.payload)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_transfer_existence_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return _transfer_object_payload_error(
                message="Desktop requires JSON object payloads for transfer existence requests.",
            )
        self._track_transfer_transport(request=request, payload=request.payload)
        status_code, response_payload = self._transfer_service.handle_asset_existence_request(request.payload)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_transfer_asset_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, TransferAssetUploadPayload):
            return MobileTransportResponse(
                status_code=400,
                payload={
                    "schema": MOBILE_TRANSFER_SCHEMA,
                    "status": "rejected",
                    "message": "Desktop did not receive the transfer asset metadata.",
                },
            )

        self._track_transfer_transport(request=request, payload=request.payload)
        status_code, response_payload = self._transfer_service.handle_asset_upload(
            metadata_payload=request.payload.metadata_payload,
            body_stream=request.payload.body_stream,
            content_length=request.payload.content_length,
            temp_file_path=request.payload.temp_file_path,
            content_sha1=request.payload.content_sha1,
        )
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _dispatch_transfer_complete_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return _transfer_object_payload_error(
                message="Desktop requires JSON object payloads for transfer completion requests.",
            )
        session_id = self._extract_transfer_session_id(request.payload)
        self._track_transfer_transport(request=request, payload=request.payload)
        status_code, response_payload = self._transfer_service.handle_complete_request(request.payload)
        self._clear_transfer_transport_tracking(session_id)
        return MobileTransportResponse(status_code=status_code, payload=response_payload)

    def _track_transfer_transport(
        self,
        *,
        request: MobileTransportRequest,
        payload: object,
    ) -> None:
        session_id = self._extract_transfer_session_id(payload)
        if session_id is None:
            return

        current_transport = request.context.transport
        request_id = request.context.request_id or "-"
        remote_address = request.context.remote_address or "-"

        with self._lock:
            previous_transport = self._transfer_transport_by_session_id.get(session_id)
            self._transfer_transport_by_session_id[session_id] = current_transport

        if previous_transport is None:
            _log(
                "debug",
                message=(
                    "MobilePairingService/transport: "
                    f"session_id={session_id} initial_transport={current_transport.value} "
                    f"operation={request.operation} request_id={request_id} remote={remote_address}"
                ),
            )
        elif previous_transport != current_transport:
            _log(
                "warning",
                message=(
                    "MobilePairingService/transport: "
                    f"session_id={session_id} transport_switch="
                    f"{previous_transport.value}->{current_transport.value} "
                    f"operation={request.operation} request_id={request_id} remote={remote_address}"
                ),
            )

    def _clear_transfer_transport_tracking(self, session_id: str | None) -> None:
        if not session_id:
            return
        with self._lock:
            self._transfer_transport_by_session_id.pop(session_id, None)

    @staticmethod
    def _extract_transfer_session_id(payload: object) -> str | None:
        payload_dict: dict[str, object] | None = None
        if isinstance(payload, dict):
            payload_dict = payload
        elif isinstance(payload, TransferAssetUploadPayload):
            payload_dict = payload.metadata_payload

        if payload_dict is None:
            return None
        session_id = payload_dict.get("session_id")
        if not isinstance(session_id, str):
            return None
        normalized_session_id = session_id.strip()
        if not normalized_session_id:
            return None
        return normalized_session_id

    def _ensure_server_started(self) -> None:
        with self._lock:
            endpoint_info = self._transport_manager.start_lan()
            self._endpoint_url = endpoint_info.endpoint_url
            self._endpoint_urls = endpoint_info.endpoint_urls

    def _build_transport_manager(self) -> MobileTransportManager:
        lan_transport = LanHttpTransportAdapter(
            listen_host=self._listen_host,
            advertised_host=self._advertised_host,
            router=self._transport_router,
            resolve_advertised_hosts=_resolve_advertised_hosts,
            format_pairing_endpoint_url=_format_pairing_endpoint_url,
            pairing_claim_path=PAIRING_CLAIM_PATH,
            pairing_protocol_schema=PAIRING_PROTOCOL_SCHEMA,
            pairing_rejected_status=PairingResultState.REJECTED.value,
            transfer_schema=MOBILE_TRANSFER_SCHEMA,
            capability_exchange_schema=MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
            capability_exchange_path=MOBILE_CAPABILITY_EXCHANGE_PATH,
            update_prompt_schema=MOBILE_UPDATE_PROMPT_SCHEMA,
            update_prompt_path=MOBILE_UPDATE_PROMPT_PATH,
            transfer_start_path=MOBILE_TRANSFER_START_PATH,
            transfer_existence_path=MOBILE_TRANSFER_EXISTENCE_PATH,
            transfer_asset_path=MOBILE_TRANSFER_ASSET_PATH,
            transfer_complete_path=MOBILE_TRANSFER_COMPLETE_PATH,
            log_handler=_log,
        )
        usb_transport = UsbWebSocketTransportAdapter(
            router=self._transport_router,
            log_handler=_log,
            is_desktop_foreground_fn=self._is_desktop_foreground,
        )
        return MobileTransportManager(
            lan_transport=lan_transport,
            usb_transport=usb_transport,
        )

    def _configure_usb_bootstrap_for_session(self, session: MobilePairingSessionDraft) -> None:
        self._configure_usb_bootstrap_for_token(
            session_id=session.session_id,
            token=session.token_for(MobilePlatform.IOS),
        )

    def _configure_usb_bootstrap_for_token(
        self,
        *,
        session_id: str,
        token: MobilePairingToken,
    ) -> None:
        bootstrap_config = UsbBootstrapConfig(
            session_id=session_id,
            one_time_passcode=token.one_time_passcode,
            suggested_port=token.suggested_usb_port,
            fallback_port_window=20,
        )
        self._transport_manager.configure_usb_bootstrap(bootstrap_config)
        usb_state = self._transport_manager.start_usb()
        probe_error = self._transport_manager.usb_last_probe_error
        probe_error_message = probe_error or "none"
        _log(
            "info",
            message=(
                "MobilePairingService/_configure_usb_bootstrap_for_token: "
                f"session_id={session_id} suggested_port={token.suggested_usb_port} "
                f"state={usb_state.value} probe_error={probe_error_message}"
            ),
        )

    def _resolve_pairing_transport(self, platform: MobilePlatform) -> str:
        if platform == MobilePlatform.IOS and self._transport_manager.usb_state == UsbTransportState.CONNECTED:
            return PAIRING_TRANSPORT_USB
        return PAIRING_TRANSPORT_LAN

    def _is_desktop_foreground(self) -> bool:
        with self._lock:
            return self._app_is_foreground

    def _on_app_foreground_state_changed(self, *, is_foreground: object, **_: object) -> None:
        with self._lock:
            self._app_is_foreground = bool(is_foreground)


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


def _transfer_object_payload_error(*, message: str) -> MobileTransportResponse:
    return MobileTransportResponse(
        status_code=400,
        payload={
            "schema": MOBILE_TRANSFER_SCHEMA,
            "status": "rejected",
            "message": message,
        },
    )


def _capability_exchange_object_payload_error(*, message: str) -> MobileTransportResponse:
    return MobileTransportResponse(
        status_code=400,
        payload={
            "schema": MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
            "status": "rejected",
            "message": message,
            "capabilities": {},
        },
    )


def _update_prompt_object_payload_error(*, message: str) -> MobileTransportResponse:
    return MobileTransportResponse(
        status_code=400,
        payload={
            "schema": MOBILE_UPDATE_PROMPT_SCHEMA,
            "status": "rejected",
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
    return _transport_is_ignorable_socket_disconnect(exc)


def _desktop_name_for_build(desktop_name: str, build_type: str) -> str:
    normalized_build_type = build_type.strip().lower() if build_type else "prod"
    if normalized_build_type == "prod":
        return desktop_name

    suffix = f"-{normalized_build_type}"
    if desktop_name.endswith(suffix):
        return desktop_name
    return f"{desktop_name}{suffix}"


def _utc_now(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _log(level: str, error_type: str = "", message: str = "", where: str = ""):
    from dt_image_search.telemetry.telemetry_client import log

    log(severity=level, error_type=error_type, where=where, message=message)
