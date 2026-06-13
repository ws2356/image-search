from __future__ import annotations

import asyncio
import logging
import os
import tempfile
import threading
from typing import Any, Callable

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from dt_image_search.identity import get_device_certificate_pem, get_device_private_key_pem
from dt_image_search.instant_sharing.contracts import TRANSFER_IMAGE_PATH, TRANSFER_TEXT_PATH
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.https_bootstrap import (
    _Deps,
    _ServiceUnavailable,
    TransferTextPayload,
    _do_transfer_image,
    _do_transfer_text,
)

_logger = logging.getLogger(__name__)

INSTANT_SHARE_TLS_SERVER_PORT = 9528


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
        deps_local: _Deps = getattr(request.app.state, "deps", None)
        if deps_local is None:
            raise _ServiceUnavailable("Instant share service not initialized")
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

    return app


class InstantShareTLSServer:
    def __init__(
        self,
        *,
        host: str = "0.0.0.0",
        port: int = INSTANT_SHARE_TLS_SERVER_PORT,
        on_error: Callable[[str], None] | None = None,
        trust_session_registry: Any = None,
        session_registry: Any = None,
        orchestrator: Any = None,
        transfer_handler: Any = None,
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
            )
            self._server = uvicorn.Server(config)
            self._thread = threading.Thread(
                target=self._server.run,
                name="instant_share_tls",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info(
            "Instant-share TLS server started on %s:%d",
            self._host, self._port,
        )
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
