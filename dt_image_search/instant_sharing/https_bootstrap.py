from __future__ import annotations

import asyncio
import logging
import socket
import threading
import uuid
from dataclasses import dataclass
from typing import Any, Callable

import uvicorn
from fastapi import Body, FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    API_PREFIX,
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
from cryptography import x509 as crypto_x509

from dt_image_search.identity import get_device_certificate_pem, store_peer_certificate
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
    # Reference to the TLS server, so the trust-confirm handler can
    # inject the newly-trusted peer certificate into the running SSL context.
    tls_server: Any | None = None


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



class TransferTextPayload(BaseModel):
    model_config = ConfigDict(extra="allow")
    text_utf8: str = ""


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

    from dt_image_search.instant_sharing.trust_server import TrustFlowType

    if trust_session.flow_type == TrustFlowType.MOBILE_TO_PC:
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
                    if deps.orchestrator is not None:
                        if active is not None:
                            _logger.info(
                                "Replacing stale active session old_id=%s new_id=%s",
                                active.connection_config.session_id, session_id,
                            )
                            session_registry.replace_active_session(connection_config)
                            deps.orchestrator.handle_trust_handshake_received(
                                session_id=session_id,
                                correlation_id=correlation_id,
                            )
                        else:
                            deps.orchestrator.handle_connection_config(connection_config)
                            deps.orchestrator.handle_trust_handshake_received(
                                session_id=session_id,
                                correlation_id=correlation_id,
                            )
                    else:
                        session_registry.replace_active_session(connection_config)
                    _logger.info("Instant-share session bootstrapped from handshake: session_id=%s", session_id)
                except Exception as exc:
                    _logger.warning(
                        "Failed to bootstrap instant-share session from handshake: %s", exc,
                    )
    else:
        _logger.info(
            "Skipping instant-share session bootstrap for pc-to-mobile flow session_id=%s",
            session_id,
        )

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
    peer_device_name = decrypted.get("peer_device_name", "")
    if isinstance(peer_device_name, str) and peer_device_name.strip():
        trust_session.set_peer_device_name(peer_device_name.strip())
    pin = trust_session.generate_pin()
    ack_envelope = trust_session.encrypted_apply_ack_envelope()
    if deps.pin_display_callback is not None:
        deps.pin_display_callback(pin)
    _logger.info("Trust apply completed: session_id=%s pin=%s", session_id_header, pin)
    return 202, {"apply_status": "accepted", **ack_envelope}


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

    peer_device_name = decrypted.get("peer_device_name", "")
    if isinstance(peer_device_name, str) and peer_device_name.strip():
        trust_session.set_peer_device_name(peer_device_name.strip())

    request_pin = decrypted.get("pin_code", "")
    request_opt = decrypted.get("opt_code", "")

    from dt_image_search.instant_sharing.trust_server import TrustFlowType

    if trust_session.flow_type == TrustFlowType.PC_TO_MOBILE:
        if not isinstance(request_opt, str) or not request_opt.strip():
            raise InstantShareError(
                error_code=ErrorCode.INVALID_REQUEST,
                message="opt_code is required for pc-to-mobile flow.",
                status_code=400,
            )
        if not trust_session.verify_opt(request_opt.strip()):
            _logger.warning(
                "[trust/confirm] invalid opt_code for pc-to-mobile flow session_id=%s",
                session_id_header,
            )
            raise InstantShareError(
                error_code=ErrorCode.PIN_MISMATCH_OR_REJECTED,
                message="OPT code does not match.",
                status_code=403,
            )
    else:
        if not isinstance(request_pin, str) or not trust_session.verify_pin(request_pin):
            raise InstantShareError(
                error_code=ErrorCode.PIN_MISMATCH_OR_REJECTED,
                message="PIN code does not match.",
                status_code=403,
            )

    mobile_cert_pem = decrypted.get("device_certificate_pem")
    if isinstance(mobile_cert_pem, str) and mobile_cert_pem.strip():
        trust_session.store_mobile_certificate(mobile_cert_pem)
        try:
            parsed = crypto_x509.load_pem_x509_certificate(mobile_cert_pem.encode("utf-8"))
            cn_attrs = parsed.subject.get_attributes_for_oid(crypto_x509.oid.NameOID.COMMON_NAME)
            mobile_device_id = cn_attrs[0].value if cn_attrs else correlation_id_header
        except Exception as exc:
            _logger.error("Failed to parse mobile certificate PEM: %s", exc)
            mobile_device_id = correlation_id_header
        store_peer_certificate(mobile_device_id, mobile_cert_pem)
        _logger.info(
            "Stored peer certificate device=%s session_id=%s flow_type=%s",
            mobile_device_id, session_id_header, trust_session.flow_type.value,
        )
        if deps.tls_server is not None:
            injected = deps.tls_server.add_peer_certificate(mobile_cert_pem)
            _logger.info(
                "Dynamic mTLS cert injection for device=%s: %s",
                mobile_device_id, "success" if injected else "failed",
            )

    trust_session.mark_trusted()
    pc_cert_pem = get_device_certificate_pem()
    trust_status = trust_session.encrypted_trust_status(pc_certificate_pem=pc_cert_pem)
    _logger.info(
        "Trust confirmed: session_id=%s correlation_id=%s flow_type=%s",
        session_id_header, correlation_id_header, trust_session.flow_type.value,
    )
    return trust_status



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

    @app.post(f"{API_PREFIX}/{{rest_of_path:path}}")
    async def _not_found(_: Request) -> JSONResponse:
        return JSONResponse(
            {"error_code": "NOT_FOUND", "message": "Unknown endpoint"},
            status_code=404,
        )

    return app


class InstantShareHTTPServer:
    def __init__(
        self,
        *,
        host: str = "0.0.0.0",
        port: int = 0,
        on_error: Callable[[str], None] | None = None,
        trust_session_registry: TrustSessionRegistry | None = None,
        session_registry: InstantShareSessionRegistry | None = None,
        orchestrator: InstantShareReceiverOrchestrator | None = None,
        transfer_handler: TransferHandler | None = None,
        pin_display_callback: Callable[[str], None] | None = None,
        qr_trigger_handler: Any = None,
        tls_server: Any | None = None,
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
            tls_server=tls_server,
        )
        self._server: uvicorn.Server | None = None
        self._thread: threading.Thread | None = None
        self._sock: socket.socket | None = None
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
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((self._host, self._port or 0))
            self._port = sock.getsockname()[1]
            self._sock = sock
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
                kwargs={"sockets": [sock]},
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
            sock = self._sock
            self._server = None
            self._thread = None
            self._sock = None
        if server is not None:
            server.should_exit = True
        if thread is not None:
            thread.join(timeout=5.0)
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        _logger.info("Instant-share HTTP server stopped")
