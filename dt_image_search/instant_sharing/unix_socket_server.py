from __future__ import annotations

import json
import logging
import os
import socket
import threading
from pathlib import Path
from typing import Any, Callable

_logger = logging.getLogger(__name__)

EXTENSION_BUNDLE_ID = "net.boldman.ausearch.share-extension"
SOCKET_RELATIVE_PATH = "Library/Application Support/au-search/qr-transfer.sock"


def _extension_socket_path(container_dir: Path | None = None) -> Path:
    home = container_dir or Path.home()
    return home / "Library/Containers" / EXTENSION_BUNDLE_ID / "Data" / SOCKET_RELATIVE_PATH


class UnixSocketHttpServer:
    def __init__(
        self,
        *,
        request_handler: Callable[[dict[str, object]], dict[str, object]] | None = None,
        socket_path: Path | None = None,
    ) -> None:
        self._request_handler = request_handler
        self._socket_path = socket_path or _extension_socket_path()
        self._server_socket: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

    @property
    def socket_path(self) -> Path:
        return self._socket_path

    def start(self) -> bool:
        sock_path = self._socket_path
        if sock_path.exists():
            os.remove(str(sock_path))
        sock_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server_sock.bind(str(sock_path))
            server_sock.listen(5)
            server_sock.settimeout(1.0)
        except OSError as exc:
            _logger.error("Failed to create Unix socket at %s: %s", sock_path, exc)
            return False

        self._server_socket = server_sock
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._serve_forever,
            name="qr_unix_socket",
            daemon=True,
        )
        self._thread.start()
        _logger.info("Unix socket HTTP server listening on %s", sock_path)
        return True

    def stop(self) -> None:
        self._stop_event.set()
        if self._server_socket is not None:
            try:
                self._server_socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._server_socket.close()
            self._server_socket = None
        if self._thread is not None:
            self._thread.join(timeout=3.0)
            self._thread = None
        if self._socket_path.exists():
            os.remove(str(self._socket_path))

    @property
    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def _serve_forever(self) -> None:
        server_sock = self._server_socket
        if server_sock is None:
            return
        while not self._stop_event.is_set():
            try:
                client, _ = server_sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with client:
                self._handle_client(client)

    def _handle_client(self, client: socket.socket) -> None:
        try:
            data = client.recv(65536)
        except OSError:
            return
        if not data:
            return
        try:
            body = self._parse_http_body(data)
        except ValueError:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 2\r\n\r\n{}")
            return
        raw = self._request_handler(body) if self._request_handler is not None else {"status": "no_handler"}
        response_body: dict[str, object] = {}
        status_code = 201
        if isinstance(raw, dict):
            response_body = {k: v for k, v in raw.items() if not k.startswith("_")}
            extra_status = raw.get("_status")
            if isinstance(extra_status, int):
                status_code = extra_status
        self._send_http_response(client, status_code, response_body)

    @staticmethod
    def _parse_http_body(data: bytes) -> dict[str, object]:
        parts = data.split(b"\r\n\r\n", 1)
        if len(parts) < 2:
            raise ValueError("No body found")
        body_bytes = parts[1]
        if not body_bytes:
            raise ValueError("Empty body")
        parsed = json.loads(body_bytes.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError("Body must be a JSON object")
        return parsed

    @staticmethod
    def _send_http_response(client: socket.socket, status: int, body: dict[str, object]) -> None:
        resp = json.dumps(body).encode("utf-8")
        status_text = {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized",
                       404: "Not Found", 410: "Gone", 500: "Internal Server Error"}.get(status, "Unknown")
        response = (
            f"HTTP/1.1 {status} {status_text}\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(resp)}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        ).encode("utf-8") + resp
        try:
            client.sendall(response)
        except OSError:
            pass
