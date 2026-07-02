from __future__ import annotations

import asyncio
import logging
import threading
from pathlib import Path
from typing import Callable
from PySide6.QtCore import QStandardPaths
from Foundation import NSFileManager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from dt_image_search.instant_sharing.qr_trigger_handler import TRIGGER_PATH

_logger = logging.getLogger(__name__)

APP_GROUP_ID = "ZU6V838VRQ.net.boldman.ausearch"
SOCKET_RELATIVE_PATH = "is.sock"
_MACOS_SUN_PATH_MAX = 104


def _group_container_socket_path(group_container_dir: Path | None = None) -> Path:
    """Resolve the Unix domain socket path inside the shared App Group container.

    Both the launch agent (non-sandboxed) and the Share Extension (sandboxed) use
    this path, bridged by the ``com.apple.security.application-groups`` entitlement.
    """
    url = NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier_(APP_GROUP_ID)
    return Path(url.path()) / SOCKET_RELATIVE_PATH


def _build_app(
    request_handler: Callable[[dict[str, object]], dict[str, object]],
) -> FastAPI:
    """Build a single-endpoint FastAPI app that delegates each request to a sync
    `request_handler` callable (off-loaded to a worker thread so the event loop
    stays free). The handler's return dict may carry a `_status` key to override
    the default HTTP 201; any leading-underscore keys are stripped from the body
    before serialization — preserving the wire shape of the previous implementation.
    """
    app = FastAPI()
    app.state.request_handler = request_handler

    @app.post(TRIGGER_PATH)
    async def trigger(request: Request) -> JSONResponse:
        body = await request.json()
        result = await asyncio.to_thread(request_handler, body)
        status_code = 201
        payload: dict[str, object] = {}
        if isinstance(result, dict):
            extra_status = result.get("_status")
            if isinstance(extra_status, int):
                status_code = extra_status
            payload = {k: v for k, v in result.items() if not k.startswith("_")}
        return JSONResponse(payload, status_code=status_code)

    return app


class UnixSocketHttpServer:
    """Unix-domain-socket HTTP server that hosts a FastAPI app via uvicorn.

    The server runs on a daemon thread; `start()` returns once uvicorn has
    bound the UDS path (or `False` on bind failure / timeout). The public
    surface (`start` / `stop` / `is_running` / `socket_path`) is unchanged
    from the previous `socket.socket`-based implementation.
    """

    _STARTUP_TIMEOUT_SECONDS = 2.0
    _STARTUP_POLL_INTERVAL = 0.05

    def __init__(
        self,
        *,
        request_handler: Callable[[dict[str, object]], dict[str, object]] | None = None,
        socket_path: Path | None = None,
    ) -> None:
        self._request_handler = request_handler
        self._socket_path = socket_path or _group_container_socket_path()
        self._server: uvicorn.Server | None = None
        self._thread: threading.Thread | None = None

    @property
    def socket_path(self) -> Path:
        return self._socket_path

    @property
    def is_running(self) -> bool:
        if self._thread is None or not self._thread.is_alive():
            return False
        if self._server is not None and self._server.should_exit:
            return False
        return True

    def start(self) -> bool:
        sock_path = self._socket_path
        if sock_path.exists():
            try:
                sock_path.unlink()
            except OSError as exc:
                _logger.error("Failed to remove stale socket at %s: %s", sock_path, exc)
                return False
        sock_path.parent.mkdir(parents=True, exist_ok=True)

        path_len = len(str(sock_path).encode("utf-8"))
        if path_len > _MACOS_SUN_PATH_MAX:
            _logger.error(
                "Socket path %s is %d bytes — exceeds AF_UNIX sun_path limit of %d bytes",
                sock_path, path_len, _MACOS_SUN_PATH_MAX,
            )
            return False

        if self._request_handler is None:
            _logger.error("No request_handler provided to UnixSocketHttpServer")
            return False

        app = _build_app(self._request_handler)
        config = uvicorn.Config(
            app,
            uds=str(sock_path),
            lifespan="off",
            access_log=False,
            log_level="warning",
            loop="asyncio",
        )
        self._server = uvicorn.Server(config)
        self._thread = threading.Thread(
            target=self._server.run,
            name="qr_unix_socket",
            daemon=True,
        )
        self._thread.start()

        if not self._wait_for_started():
            _logger.error("Unix socket server failed to bind %s within %.1fs",
                          sock_path, self._STARTUP_TIMEOUT_SECONDS)
            self.stop()
            return False

        _logger.info("Unix socket HTTP server listening on %s", sock_path)
        return True

    def _wait_for_started(self) -> bool:
        server = self._server
        if server is None:
            return False
        deadline = self._STARTUP_TIMEOUT_SECONDS
        elapsed = 0.0
        while elapsed < deadline:
            if server.started:
                return True
            threading.Event().wait(self._STARTUP_POLL_INTERVAL)
            elapsed += self._STARTUP_POLL_INTERVAL
        return bool(server.started)

    def stop(self) -> None:
        server = self._server
        thread = self._thread
        self._server = None
        self._thread = None
        if server is not None:
            server.should_exit = True
        if thread is not None:
            thread.join(timeout=3.0)
        if self._socket_path.exists():
            try:
                self._socket_path.unlink()
            except OSError:
                pass
