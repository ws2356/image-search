from __future__ import annotations

import asyncio
import base64
import json
import logging
import threading
import uuid
from dataclasses import dataclass
from typing import Any, Callable

import uvicorn
from fastapi import Body, FastAPI, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict, RootModel

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    API_PREFIX,
    QR_CLAIM_PATH,
    TRANSFER_IMAGE_PATH,
    TRANSFER_TEXT_PATH,
    TRUST_APPLY_PATH,
    TRUST_CONFIRM_PATH,
    TRUST_HANDSHAKE_PATH,
    ErrorCode,
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry
from dt_image_search.instant_sharing.transfer_server import TransferHandler
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry

_logger = logging.getLogger(__name__)


class _ServiceUnavailable(RuntimeError):
    pass


@dataclass
class _Deps:
    trust_session_registry: TrustSessionRegistry | None = None
    session_registry: InstantShareSessionRegistry | None = None
    orchestrator: InstantShareReceiverOrchestrator | None = None
    transfer_handler: TransferHandler | None = None
    pin_display_callback: Callable[[str], None] | None = None
    # TODO: Define a proper protocol for this instead of Any
    qr_trigger_handler: Any = None


class TrustHandshakeRequest(BaseModel):
    model_config = ConfigDict(extra="allow")
    mobile_dh_public_key: str
    mobile_nonce: str
    payload_class: str = "text"
    target_intent: str = "clipboard_only"
    trust_mode: str = "first_share"
    mobile_port: int = 1
    mobile_ip_list: list[str] = ["127.0.0.1"]
    correlation_id: str | None = None


_TrustEnvelope = RootModel[dict[str, Any]]


class TransferTextPayload(BaseModel):
    model_config = ConfigDict(extra="allow")
    text_utf8: str = ""


class QrClaimRequest(BaseModel):
    model_config = ConfigDict(extra="allow")
    stash_id: str
    opt: str


def _deps_from(request: Request) -> _Deps:
    deps: _Deps | None = getattr(request.app.state, "deps", None)
    if deps is None:
        raise _ServiceUnavailable("Instant share service not initialized")
    return deps


def _do_trust_handshake(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    body: TrustHandshakeRequest,
) -> dict[str, object]:
    if deps.trust_session_registry is None:
        raise _ServiceUnavailable("Trust service not initialized")

    session_id = session_id_header or str(uuid.uuid4())
    correlation_id = correlation_id_header

    trust_session = deps.trust_session_registry.get_session(session_id)
    if trust_session is None:
        trust_session = deps.trust_session_registry.create_session(
            session_id=session_id,
            correlation_id=correlation_id or session_id,
        )
        _logger.info("Auto-created trust session for handshake: session_id=%s", session_id)

    session_registry = deps.session_registry
    if session_registry is not None:
        active = session_registry.get_active_session()
        if active is None or active.connection_config.session_id != session_id:
            try:
                metadata = InstantShareMetadata(
                    payload_class=PayloadClass(body.payload_class),
                    target_intent=TargetIntent(body.target_intent),
                    trust_mode=TrustMode(body.trust_mode),
                )
                connection_config = ConnectionConfig(
                    session_id=session_id,
                    mobile_port=body.mobile_port,
                    mobile_ip_list=tuple(body.mobile_ip_list),
                    correlation_id=correlation_id,
                    metadata=metadata,
                )
                # TODO: When would orchestrator be None? Could we prevent that?
                if deps.orchestrator is not None:
                    # TODO: Consider 1. removing handle_connection_config
                    # 2. let handle_trust_handshake_received init the session if not exist. If there is already an active session having mismatching id, just replace it with the new one. This would make the app more resilient to edge cases like client abandoning a session and starting a new one without proper teardown.
                    deps.orchestrator.handle_connection_config(connection_config)
                    deps.orchestrator.handle_trust_handshake_received(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                else:
                    session_registry.bootstrap(connection_config)
                _logger.info("Instant-share session bootstrapped from handshake: session_id=%s", session_id)
            except Exception as exc:
                _logger.warning("Failed to bootstrap instant-share session from handshake: %s", exc)

    trust_session.store_mobile_handshake(
        mobile_dh_public_key=body.mobile_dh_public_key,
        mobile_nonce=body.mobile_nonce,
    )
    trust_session.establish_session_key()
    _logger.info("Trust handshake completed: session_id=%s correlation_id=%s", session_id, correlation_id)
    return trust_session.handshake_response()


def _do_trust_apply(
    deps: _Deps,
    *,
    session_id_header: str,
    envelope: dict[str, Any],
) -> tuple[int, dict[str, object]]:
    if deps.trust_session_registry is None:
        raise _ServiceUnavailable("Trust service not initialized")
    try:
        trust_session = deps.trust_session_registry.require_session(session_id_header)
    except InstantShareError:
        raise InstantShareError(
            error_code=ErrorCode.HANDSHAKE_REQUIRED,
            message="No active session found",
        ) from None
    if not trust_session.is_session_key_established:
        raise InstantShareError(
            error_code=ErrorCode.HANDSHAKE_REQUIRED,
            message="Session key not established. Complete handshake first.",
        )
    decrypted = trust_session.decrypt_apply_request(envelope)
    action = decrypted.get("action")
    if action != "request_pin":
        raise InstantShareError(
            error_code=ErrorCode.INVALID_REQUEST,
            message=f"Unsupported action: {action}",
        )
    pin = trust_session.generate_pin()
    pin_envelope = trust_session.encrypted_pin_envelope()
    if deps.pin_display_callback is not None:
        deps.pin_display_callback(pin)
    _logger.info("Trust apply completed: session_id=%s pin=%s", session_id_header, pin)
    return 202, {"apply_status": "accepted", **pin_envelope}


def _do_trust_confirm(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    envelope: dict[str, Any],
) -> dict[str, object]:
    if deps.trust_session_registry is None:
        raise _ServiceUnavailable("Trust service not initialized")
    try:
        trust_session = deps.trust_session_registry.require_session(session_id_header)
    except InstantShareError:
        raise InstantShareError(
            error_code=ErrorCode.HANDSHAKE_REQUIRED,
            message="No active session found",
        ) from None
    if not trust_session.is_session_key_established:
        raise InstantShareError(
            error_code=ErrorCode.HANDSHAKE_REQUIRED,
            message="Session key not established. Complete handshake first.",
        )
    decrypted = trust_session.decrypt_confirm_request(envelope)
    action = decrypted.get("action")
    if action != "confirm":
        raise InstantShareError(
            error_code=ErrorCode.INVALID_REQUEST,
            message=f"Unsupported action: {action}",
        )
    trust_session.mark_trusted()
    trust_status = trust_session.encrypted_trust_status()
    _logger.info("Trust confirmed: session_id=%s correlation_id=%s", session_id_header, correlation_id_header)
    return trust_status


def _do_transfer_text(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    raw_body: bytes,
    payload_text_utf8: str,
) -> dict[str, object]:
    if deps.trust_session_registry is None or deps.transfer_handler is None or deps.session_registry is None:
        raise _ServiceUnavailable("Transfer service not initialized")
    trust_session = deps.trust_session_registry.get_session(session_id_header)
    if trust_session is None:
        raise InstantShareError(
            error_code=ErrorCode.SESSION_NOT_FOUND,
            message="No active session found",
            status_code=404,
        )
    if not trust_session.is_trusted:
        raise InstantShareError(
            error_code=ErrorCode.TRUST_REQUIRED,
            message="Trust handshake must be completed before transfer",
            status_code=403,
        )
    result = deps.transfer_handler.receive_text(
        session_id=session_id_header,
        correlation_id=correlation_id_header,
        body=raw_body,
    )
    _logger.info("Transfer text received: session_id=%s correlation_id=%s", session_id_header, correlation_id_header)
    if deps.orchestrator is not None:
        try:
            deps.orchestrator.handle_transfer_received(
                session_id=session_id_header,
                correlation_id=correlation_id_header,
            )
            deps.orchestrator.handle_delivery_complete(
                session_id=session_id_header,
                correlation_id=correlation_id_header,
                text_content=payload_text_utf8,
            )
        except Exception as exc:
            _logger.warning("Failed to publish transfer lifecycle event: %s", exc)
    return {"state": "delivered", **result.as_dict()}


# TODO: DO NOT read the bytes into memory, instead stream it into a temp file
def _do_transfer_image(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    raw_body: bytes,
    content_type: str,
    filename: str | None,
) -> dict[str, object]:
    if deps.trust_session_registry is None or deps.transfer_handler is None or deps.session_registry is None:
        raise _ServiceUnavailable("Transfer service not initialized")
    trust_session = deps.trust_session_registry.get_session(session_id_header)
    if trust_session is None:
        raise InstantShareError(
            error_code=ErrorCode.SESSION_NOT_FOUND,
            message="No active session found",
            status_code=404,
        )
    if not trust_session.is_trusted:
        raise InstantShareError(
            error_code=ErrorCode.TRUST_REQUIRED,
            message="Trust handshake must be completed before transfer",
            status_code=403,
        )
    result = deps.transfer_handler.receive_image(
        session_id=session_id_header,
        correlation_id=correlation_id_header,
        body=raw_body,
        content_type=content_type,
        filename=filename,
    )
    _logger.info("Transfer image received: session_id=%s correlation_id=%s", session_id_header, correlation_id_header)
    file_path = result.output_file_path
    if deps.orchestrator is not None:
        try:
            deps.orchestrator.handle_transfer_received(
                session_id=session_id_header,
                correlation_id=correlation_id_header,
            )
            deps.orchestrator.handle_delivery_complete(
                session_id=session_id_header,
                correlation_id=correlation_id_header,
                file_path=file_path,
            )
        except Exception as exc:
            _logger.warning("Failed to publish transfer lifecycle event: %s", exc)
    return {"state": "delivered", **result.as_dict()}


def _do_qr_claim(deps: _Deps, *, body: dict[str, Any]) -> tuple[int, dict[str, Any] | bytes, dict[str, str] | None]:
    if deps.qr_trigger_handler is None:
        raise _ServiceUnavailable("QR trigger service not initialized")
    result = deps.qr_trigger_handler.handle_claim(body)
    result_status = result.get("_status", 200)
    if not isinstance(result_status, int):
        result_status = 200
    if result.get("status") == "claimed" and "content" in result:
        resp_bytes = str(result.get("content", "")).encode("utf-8")
        headers = {"Content-Type": str(result.get("content_type", "text/plain"))}
        if result.get("filename"):
            headers["X-Original-Filename"] = str(result["filename"])
        return result_status, resp_bytes, headers
    if result.get("status") == "claimed" and "file_bytes_base64" in result:
        raw = result["file_bytes_base64"]
        resp_bytes = raw if isinstance(raw, bytes) else base64.b64decode(str(raw))
        headers = {"Content-Type": str(result.get("content_type", "application/octet-stream"))}
        if result.get("filename"):
            headers["X-Original-Filename"] = str(result["filename"])
        return result_status, resp_bytes, headers
    safe = {k: v for k, v in result.items() if not k.startswith("_")}
    return result_status, safe, None


def _build_app(deps: _Deps) -> FastAPI:
    app = FastAPI()
    app.state.deps = deps

    @app.exception_handler(InstantShareError)
    async def _instant_share_error_handler(_: Request, exc: InstantShareError) -> JSONResponse:
        return JSONResponse(
            {"error_code": exc.error_code.value, "message": exc.message},
            status_code=exc.status_code,
        )

    @app.exception_handler(_ServiceUnavailable)
    async def _service_unavailable_handler(_: Request, exc: _ServiceUnavailable) -> JSONResponse:
        return JSONResponse(
            {"error_code": "SERVICE_UNAVAILABLE", "message": str(exc) or "Service unavailable"},
            status_code=503,
        )

    @app.post(TRUST_HANDSHAKE_PATH)
    async def trust_handshake(request: Request, body: TrustHandshakeRequest) -> JSONResponse:
        deps_local = _deps_from(request)
        result = await asyncio.to_thread(
            _do_trust_handshake,
            deps_local,
            session_id_header=request.headers.get("X-Session-Id", ""),
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            body=body,
        )
        return JSONResponse(result, status_code=200)

    @app.post(TRUST_APPLY_PATH)
    async def trust_apply(request: Request, envelope: dict[str, Any] = Body(...)) -> JSONResponse:
        deps_local = _deps_from(request)
        status, payload = await asyncio.to_thread(
            _do_trust_apply,
            deps_local,
            session_id_header=request.headers.get("X-Session-Id", ""),
            envelope=envelope,
        )
        return JSONResponse(payload, status_code=status)

    @app.post(TRUST_CONFIRM_PATH)
    async def trust_confirm(request: Request, envelope: dict[str, Any] = Body(...)) -> JSONResponse:
        deps_local = _deps_from(request)
        result = await asyncio.to_thread(
            _do_trust_confirm,
            deps_local,
            session_id_header=request.headers.get("X-Session-Id", ""),
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            envelope=envelope,
        )
        return JSONResponse(result, status_code=200)

    @app.post(TRANSFER_TEXT_PATH)
    async def transfer_text(request: Request, payload: TransferTextPayload) -> JSONResponse:
        deps_local = _deps_from(request)
        raw_body = await request.body()
        try:
            payload_text_utf8 = payload.text_utf8
        except Exception:
            payload_text_utf8 = ""
        result = await asyncio.to_thread(
            _do_transfer_text,
            deps_local,
            session_id_header=request.headers.get("X-Session-Id", ""),
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            raw_body=raw_body,
            payload_text_utf8=payload_text_utf8,
        )
        return JSONResponse(result, status_code=200)

    @app.post(TRANSFER_IMAGE_PATH)
    async def transfer_image(request: Request) -> JSONResponse:
        deps_local = _deps_from(request)
        raw_body = await request.body()
        result = await asyncio.to_thread(
            _do_transfer_image,
            deps_local,
            session_id_header=request.headers.get("X-Session-Id", ""),
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            raw_body=raw_body,
            content_type=request.headers.get("Content-Type", "application/octet-stream"),
            filename=request.headers.get("X-Instant-Share-Filename"),
        )
        return JSONResponse(result, status_code=200)

    @app.post(QR_CLAIM_PATH)
    async def qr_claim(request: Request, body: dict[str, Any] = Body(...)) -> Response:
        deps_local = _deps_from(request)
        status, payload, headers = await asyncio.to_thread(_do_qr_claim, deps_local, body=body)
        if headers is not None and isinstance(payload, bytes):
            return Response(content=payload, status_code=status, headers=headers)
        return JSONResponse(payload, status_code=status)

    @app.post(f"{API_PREFIX}/{{rest_of_path:path}}")
    async def _not_found(_: Request) -> JSONResponse:
        return JSONResponse(
            {"error_code": "NOT_FOUND", "message": "Unknown endpoint"},
            status_code=404,
        )

    return app


# TODO: Avoid hardcoding the port number, instead auto-select an available port
# and provide a way for the caller to discover it.
class InstantShareHTTPServer:
    def __init__(
        self,
        *,
        host: str = "0.0.0.0",
        port: int = 9527,
        on_error: Callable[[str], None] | None = None,
        trust_session_registry: TrustSessionRegistry | None = None,
        session_registry: InstantShareSessionRegistry | None = None,
        orchestrator: InstantShareReceiverOrchestrator | None = None,
        transfer_handler: TransferHandler | None = None,
        pin_display_callback: Callable[[str], None] | None = None,
        qr_trigger_handler: Any = None,
    ) -> None:
        self._host = host
        self._port = port
        self._on_error = on_error
        self._deps = _Deps(
            trust_session_registry=trust_session_registry,
            session_registry=session_registry,
            orchestrator=orchestrator,
            transfer_handler=transfer_handler,
            pin_display_callback=pin_display_callback,
            qr_trigger_handler=qr_trigger_handler,
        )
        self._server: uvicorn.Server | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.RLock()

    @property
    def is_running(self) -> bool:
        with self._lock:
            if self._thread is None or not self._thread.is_alive():
                return False
            if self._server is not None and self._server.should_exit:
                return False
            return True

    @property
    def port(self) -> int:
        return self._port

    def start(self) -> bool:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return True
            app = _build_app(self._deps)
            config = uvicorn.Config(
                app,
                host=self._host,
                port=self._port,
                lifespan="off",
                access_log=False,
                log_level="warning",
                loop="asyncio",
            )
            self._server = uvicorn.Server(config)
            self._thread = threading.Thread(
                target=self._server.run,
                name="instant_share_http",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info("Instant-share HTTP server started on %s:%d", self._host, self._port)
        return True

    def stop(self) -> None:
        with self._lock:
            server = self._server
            thread = self._thread
            self._server = None
            self._thread = None
        if server is not None:
            server.should_exit = True
        if thread is not None:
            thread.join(timeout=5.0)
        _logger.info("Instant-share HTTP server stopped")
