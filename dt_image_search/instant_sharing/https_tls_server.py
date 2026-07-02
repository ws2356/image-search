from __future__ import annotations

import asyncio
import logging
import os
import socket
import ssl
import tempfile
import threading
from typing import Any, Callable

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict, RootModel

from dt_image_search.identity import (
    get_device_certificate_pem,
    get_device_private_key_pem,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.https_bootstrap import (
    _Deps,
    _ServiceUnavailable,
    TransferTextPayload,
)
from dt_image_search.instant_sharing.contracts import (
    TRANSFER_DOWNLOAD_PATH,
    TRANSFER_IMAGE_PATH,
    TRANSFER_MANIFEST_PATH,
    TRANSFER_TEXT_PATH,
    ErrorCode,
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.security import verify_session_signature

_TrustEnvelope = RootModel[dict[str, Any]]


_logger = logging.getLogger(__name__)


_SIGNATURE_REQUIRED_HEADERS = (
    "X-Session-Id",
    "X-Peer-Device-Id",
    "X-Session-Signature",
    "X-Session-Signature-Alg",
)


def _extract_signature_headers(request: Request) -> tuple[str, str, str, str]:
    """Extract and validate the signature headers from a transfer request.

    Returns:
        (session_id, peer_device_id, signature, algorithm)

    Raises:
        InstantShareError if any required header is missing.
    """
    session_id = request.headers.get("X-Session-Id", "")
    peer_device_id = request.headers.get("X-Peer-Device-Id", "")
    signature = request.headers.get("X-Session-Signature", "")
    algorithm = request.headers.get("X-Session-Signature-Alg", "")
    _logger.info(
        "[TLS] signature headers session_id=%s peer_device_id=%s has_signature=%s algorithm=%s",
        session_id,
        peer_device_id,
        bool(signature),
        algorithm,
    )
    missing = [h for h, v in (
        ("X-Session-Id", session_id),
        ("X-Peer-Device-Id", peer_device_id),
        ("X-Session-Signature", signature),
        ("X-Session-Signature-Alg", algorithm),
    ) if not v]
    if missing:
        _logger.warning(
            "[TLS] missing signature headers: %s",
            ", ".join(missing),
        )
        raise InstantShareError(
            error_code=ErrorCode.INVALID_REQUEST,
            message=f"Missing required signature headers: {', '.join(missing)}",
            status_code=401,
        )
    return session_id, peer_device_id, signature, algorithm


def _do_transfer_text(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    raw_body: bytes,
    payload_text_utf8: str,
    peer_device_name: str = "",
) -> dict[str, object]:
    if deps.trust_session_registry is None or deps.transfer_handler is None or deps.session_registry is None:
        raise _ServiceUnavailable("Transfer service not initialized")
    trust_session = deps.trust_session_registry.get_session(session_id_header)
    is_revisit = False
    if trust_session is None:
        if not _try_create_revisit_session(
            deps,
            session_id_header=session_id_header,
            correlation_id_header=correlation_id_header,
            payload_class=PayloadClass.TEXT,
            target_intent=TargetIntent.CLIPBOARD_ONLY,
            peer_device_name=peer_device_name,
        ):
            raise InstantShareError(
                error_code=ErrorCode.SESSION_NOT_FOUND,
                message="No active session found",
                status_code=404,
            )
        is_revisit = True
    elif not trust_session.is_trusted:
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
            if not is_revisit:
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


def _do_transfer_image(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    raw_body: bytes | None = None,
    content_type: str,
    filename: str | None,
    peer_device_name: str = "",
    temp_file_path: str | None = None,
    image_count: int = 0,
) -> dict[str, object]:
    if deps.trust_session_registry is None or deps.transfer_handler is None or deps.session_registry is None:
        raise _ServiceUnavailable("Transfer service not initialized")
    trust_session = deps.trust_session_registry.get_session(session_id_header)
    is_revisit = False
    if trust_session is None:
        if not _try_create_revisit_session(
            deps,
            session_id_header=session_id_header,
            correlation_id_header=correlation_id_header,
            payload_class=PayloadClass.IMAGE,
            target_intent=TargetIntent.CLIPBOARD_OR_FILE,
            peer_device_name=peer_device_name,
            image_count=image_count,
        ):
            raise InstantShareError(
                error_code=ErrorCode.SESSION_NOT_FOUND,
                message="No active session found",
                status_code=404,
            )
        is_revisit = True
    elif not trust_session.is_trusted:
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
        temp_file_path=temp_file_path,
    )
    _logger.info("Transfer image received: session_id=%s correlation_id=%s", session_id_header, correlation_id_header)
    file_path = result.output_file_path
    if deps.orchestrator is not None:
        try:
            if not is_revisit:
                batch_complete = deps.orchestrator.handle_transfer_received(
                    session_id=session_id_header,
                    correlation_id=correlation_id_header,
                    image_count=image_count if image_count > 0 else None,
                )
            else:
                # For revisit transfers, also call handle_transfer_received to
                # increment received_count.  Pass image_count only on the first
                # request (when session.image_count is still 0), so subsequent
                # requests don't overwrite it.
                first_image = image_count if image_count > 0 else None
                batch_complete = deps.orchestrator.handle_transfer_received(
                    session_id=session_id_header,
                    correlation_id=correlation_id_header,
                    image_count=first_image,
                )

            # Only deliver when batch is complete (single images always deliver)
            if batch_complete:
                deps.orchestrator.handle_delivery_complete(
                    session_id=session_id_header,
                    correlation_id=correlation_id_header,
                    file_path=file_path,
                )
        except Exception as exc:
            _logger.warning("Failed to publish transfer lifecycle event: %s", exc)
    return {"state": "delivered", **result.as_dict()}


def _do_transfer_manifest(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
) -> dict[str, object]:
    """Return a JSON manifest listing all files available for download.
    iOS calls this first to discover what's available, then downloads each file
    via /transfer/download/<index>."""
    if deps.trust_session_registry is None or deps.session_registry is None:
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
    stash_id = trust_session.stash_id
    if stash_id is None:
        raise InstantShareError(
            error_code=ErrorCode.INVALID_REQUEST,
            message="No stash associated with this session",
            status_code=400,
        )
    if deps.qr_trigger_handler is None:
        raise _ServiceUnavailable("QR trigger service not initialized")
    result = deps.qr_trigger_handler.retrieve_stash_content(stash_id)
    _logger.info(
        "[transfer/manifest] served manifest stash_id=%s file_count=%s session_id=%s",
        stash_id, result.get("file_count", 0), session_id_header,
    )
    return {k: v for k, v in result.items() if not k.startswith("_")}


def _do_transfer_download_file(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    file_index: int,
) -> tuple[int, bytes, str, str]:
    """Serve a single file's bytes by index from a stash.
    Returns (status_code, bytes, content_type, filename)."""
    if deps.trust_session_registry is None:
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
    stash_id = trust_session.stash_id
    if stash_id is None:
        raise InstantShareError(
            error_code=ErrorCode.INVALID_REQUEST,
            message="No stash associated with this session",
            status_code=400,
        )
    if deps.qr_trigger_handler is None:
        raise _ServiceUnavailable("QR trigger service not initialized")
    status, file_bytes, content_type, filename = deps.qr_trigger_handler.retrieve_stash_file(stash_id, file_index)
    if status != 200:
        _logger.warning(
            "[transfer/download/%d] FAILED stash_id=%s status=%d session_id=%s",
            file_index, stash_id, status, session_id_header,
        )
    else:
        _logger.info(
            "[transfer/download/%d] delivered stash_id=%s content_type=%s bytes=%d session_id=%s",
            file_index, stash_id, content_type, len(file_bytes), session_id_header,
        )
    return status, file_bytes, content_type, filename


def _try_create_revisit_session(
    deps: _Deps,
    *,
    session_id_header: str,
    correlation_id_header: str,
    payload_class: PayloadClass,
    target_intent: TargetIntent,
    peer_device_name: str = "",
    image_count: int = 0,
) -> bool:
    if deps.session_registry is None or deps.orchestrator is None:
        return False
    try:
        metadata = InstantShareMetadata(
            payload_class=payload_class,
            target_intent=target_intent,
            trust_mode=TrustMode.TRUSTED_DIRECT,
        )
        connection_config = ConnectionConfig(
            session_id=session_id_header,
            mobile_port=1,
            mobile_ip_list=("127.0.0.1",),
            correlation_id=correlation_id_header or session_id_header,
            metadata=metadata,
        )
        connection_config.validate()
    except Exception:
        _logger.warning(
            "Failed to build revisit connection config session_id=%s",
            session_id_header,
        )
        return False
    deps.orchestrator.handle_revisit_transfer(
        connection_config=connection_config,
        peer_device_name=peer_device_name,
        image_count=image_count if image_count > 0 else None,
    )
    return True

def _build_tls_app(deps: _Deps) -> FastAPI:
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

    @app.post(TRANSFER_TEXT_PATH)
    async def transfer_text(request: Request, payload: TransferTextPayload) -> JSONResponse:
        deps_local: _Deps = getattr(request.app.state, "deps", None)
        if deps_local is None:
            raise _ServiceUnavailable("Instant share service not initialized")
        session_id, peer_device_id, signature, algorithm = _extract_signature_headers(request)
        await asyncio.to_thread(
            verify_session_signature, peer_device_id, session_id, signature, algorithm,
        )
        raw_body = await request.body()
        try:
            payload_text_utf8 = payload.text_utf8
        except Exception:
            payload_text_utf8 = ""
        peer_device_name = request.headers.get("X-Peer-Device-Name", "")
        _logger.info(
            "[TLS] transfer_text session_id=%s peer_device_id=%s",
            session_id, peer_device_id,
        )
        result = await asyncio.to_thread(
            _do_transfer_text,
            deps_local,
            session_id_header=session_id,
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            raw_body=raw_body,
            payload_text_utf8=payload_text_utf8,
            peer_device_name=peer_device_name,
        )
        return JSONResponse(result, status_code=200)

    @app.post(TRANSFER_IMAGE_PATH)
    async def transfer_image(request: Request) -> JSONResponse:
        deps_local: _Deps = getattr(request.app.state, "deps", None)
        if deps_local is None:
            raise _ServiceUnavailable("Instant share service not initialized")
        session_id, peer_device_id, signature, algorithm = _extract_signature_headers(request)
        await asyncio.to_thread(
            verify_session_signature, peer_device_id, session_id, signature, algorithm,
        )
        peer_device_name = request.headers.get("X-Peer-Device-Name", "")
        _logger.info(
            "[TLS] transfer_image session_id=%s peer_device_id=%s",
            session_id, peer_device_id,
        )
        content_type = request.headers.get("Content-Type", "application/octet-stream")
        filename = request.headers.get("X-Instant-Share-Filename")
        correlation_id_header = request.headers.get("X-Correlation-Id", "")
        image_count_header = request.headers.get("X-Image-Count")
        image_count = int(image_count_header) if image_count_header else 0

        from tempfile import NamedTemporaryFile
        tmp = NamedTemporaryFile(delete=False, suffix=".upload")
        try:
            async for chunk in request.stream():
                tmp.write(chunk)
            tmp.flush()
            temp_path = tmp.name
        finally:
            tmp.close()

        try:
            result = await asyncio.to_thread(
                _do_transfer_image,
                deps_local,
                session_id_header=session_id,
                correlation_id_header=correlation_id_header,
                raw_body=None,
                content_type=content_type,
                filename=filename,
                peer_device_name=peer_device_name,
                temp_file_path=temp_path,
                image_count=image_count,
            )
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
        return JSONResponse(result, status_code=200)

    @app.post(TRANSFER_MANIFEST_PATH)
    async def transfer_manifest(request: Request) -> JSONResponse:
        deps_local: _Deps = getattr(request.app.state, "deps", None)
        if deps_local is None:
            raise _ServiceUnavailable("Instant share service not initialized")
        session_id, peer_device_id, signature, algorithm = _extract_signature_headers(request)
        await asyncio.to_thread(
            verify_session_signature, peer_device_id, session_id, signature, algorithm,
        )
        _logger.info(
            "[TLS] transfer_manifest session_id=%s peer_device_id=%s",
            session_id, peer_device_id,
        )
        result = await asyncio.to_thread(
            _do_transfer_manifest,
            deps_local,
            session_id_header=session_id,
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
        )
        return JSONResponse(result, status_code=200)

    @app.post(TRANSFER_DOWNLOAD_PATH + "/{file_index}")
    async def transfer_download_file(request: Request, file_index: int) -> Response:
        deps_local: _Deps = getattr(request.app.state, "deps", None)
        if deps_local is None:
            raise _ServiceUnavailable("Instant share service not initialized")
        session_id, peer_device_id, signature, algorithm = _extract_signature_headers(request)
        await asyncio.to_thread(
            verify_session_signature, peer_device_id, session_id, signature, algorithm,
        )
        _logger.info(
            "[TLS] transfer_download_file session_id=%s index=%d peer_device_id=%s",
            session_id, file_index, peer_device_id,
        )
        status, payload, content_type, filename = await asyncio.to_thread(
            _do_transfer_download_file,
            deps_local,
            session_id_header=session_id,
            correlation_id_header=request.headers.get("X-Correlation-Id", ""),
            file_index=file_index,
        )
        if status == 200:
            headers: dict[str, str] = {"Content-Type": content_type}
            if filename:
                headers["X-Original-Filename"] = filename
            return Response(content=payload, status_code=status, headers=headers)
        error_msg = "Invalid request"
        if status == 404:
            error_msg = "Stash not found or source file not accessible"
        elif status == 410:
            error_msg = "Stash expired or source file unavailable"
        elif status == 400:
            error_msg = f"File index {file_index} out of range"
        _logger.warning(
            "[transfer/download/%d] ERROR RESPONSE status=%d session_id=%s message=%s",
            file_index, status, session_id, error_msg,
        )
        return JSONResponse(
            {"error_code": "INVALID_REQUEST", "message": error_msg},
            status_code=status,
        )

    return app


class InstantShareTLSServer:
    def __init__(
        self,
        *,
        host: str = "0.0.0.0",
        port: int = 0,
        on_error: Callable[[str], None] | None = None,
        trust_session_registry: Any = None,
        session_registry: Any = None,
        orchestrator: Any = None,
        transfer_handler: Any = None,
        pin_display_callback: Callable[[str, str], None] | None = None,
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
        self._sock: socket.socket | None = None
        self._lock = threading.RLock()
        self._cert_file: tempfile.NamedTemporaryFile | None = None
        self._key_file: tempfile.NamedTemporaryFile | None = None

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
            cert_pem = get_device_certificate_pem()
            key_pem = get_device_private_key_pem()
            self._cert_file = tempfile.NamedTemporaryFile(
                suffix=".pem", mode="w", delete=False
            )
            self._cert_file.write(cert_pem)
            self._cert_file.flush()
            self._key_file = tempfile.NamedTemporaryFile(
                suffix=".pem", mode="w", delete=False
            )
            self._key_file.write(key_pem)
            self._key_file.flush()

            app = _build_tls_app(self._deps)
            config = uvicorn.Config(
                app,
                host=self._host,
                port=self._port,
                lifespan="off",
                access_log=False,
                log_level="warning",
                loop="asyncio",
                ssl_certfile=self._cert_file.name,
                ssl_keyfile=self._key_file.name,
                ssl_cert_reqs=ssl.CERT_NONE,
            )
            self._server = uvicorn.Server(config)
            self._thread = threading.Thread(
                target=self._server.run,
                kwargs={"sockets": [sock]},
                name="instant_share_tls",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info(
            "Instant-share TLS server started on %s:%d (HTTPS with app-layer signature auth)",
            self._host, self._port,
        )
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
        cert_path = None
        key_path = None
        with self._lock:
            if self._cert_file is not None:
                cert_path = self._cert_file.name
                self._cert_file.close()
                self._cert_file = None
            if self._key_file is not None:
                key_path = self._key_file.name
                self._key_file.close()
                self._key_file = None
        if cert_path is not None and os.path.exists(cert_path):
            os.unlink(cert_path)
        if key_path is not None and os.path.exists(key_path):
            os.unlink(key_path)
        _logger.info("Instant-share TLS server stopped")
