from __future__ import annotations

import json
import logging
import threading
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Callable

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    API_PREFIX,
    TRUST_HANDSHAKE_PATH,
    TRUST_APPLY_PATH,
    TRUST_CONFIRM_PATH,
    TRANSFER_TEXT_PATH,
    TRANSFER_IMAGE_PATH,
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.instant_sharing.transfer_server import TransferHandler
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


_logger = logging.getLogger(__name__)


class _InstantShareHandler(BaseHTTPRequestHandler):
    on_error: Callable[[str], None] | None = None
    trust_session_registry: TrustSessionRegistry | None = None
    session_registry: InstantShareSessionRegistry | None = None
    orchestrator: InstantShareReceiverOrchestrator | None = None
    transfer_handler: TransferHandler | None = None
    pin_display_callback: Callable[[str], None] | None = None

    def log_message(self, format: str, *args: object) -> None:
        _logger.debug("InstantShareHTTPServer: " + format % args)

    def do_POST(self) -> None:
        if self.path == TRUST_HANDSHAKE_PATH:
            self._handle_trust_handshake()
        elif self.path == TRUST_APPLY_PATH:
            self._handle_trust_apply()
        elif self.path == TRUST_CONFIRM_PATH:
            self._handle_trust_confirm()
        elif self.path == TRANSFER_TEXT_PATH:
            self._handle_transfer_text()
        elif self.path == TRANSFER_IMAGE_PATH:
            self._handle_transfer_image()
        else:
            self._send_json(404, {"error_code": "NOT_FOUND", "message": "Unknown endpoint"})

    def _handle_trust_handshake(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        session_registry = self.__class__.session_registry
        if trust_registry is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "Trust service not initialized"})
            return
        session_id = self.headers.get("X-Session-Id", "")
        correlation_id = self.headers.get("X-Correlation-Id", "")
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            payload = json.loads(raw_body.decode("utf-8"))
        except Exception:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Invalid JSON body"})
            return
        if not isinstance(payload, dict):
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Request body must be a JSON object"})
            return
        mobile_dh_public_key = payload.get("mobile_dh_public_key")
        mobile_nonce = payload.get("mobile_nonce")
        if not mobile_dh_public_key or not mobile_nonce:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Missing mobile_dh_public_key or mobile_nonce"})
            return

        if not session_id:
            session_id = str(uuid.uuid4())

        trust_session = trust_registry.get_session(session_id)
        if trust_session is None:
            trust_session = trust_registry.create_session(
                session_id=session_id,
                correlation_id=correlation_id or session_id,
            )
            _logger.info(
                "Auto-created trust session for handshake: session_id=%s",
                session_id,
            )

        # Bootstrap the instant-share session from connection config in handshake body
        orchestrator = self.__class__.orchestrator
        if session_registry is not None and session_registry.get_active_session() is None:
            try:
                metadata = InstantShareMetadata(
                    payload_class=PayloadClass(payload.get("payload_class", "text")),
                    target_intent=TargetIntent(payload.get("target_intent", "clipboard_only")),
                    trust_mode=TrustMode(payload.get("trust_mode", "first_share")),
                )
                connection_config = ConnectionConfig(
                    session_id=session_id,
                    mobile_port=payload.get("mobile_port", 1),
                    mobile_ip_list=tuple(payload.get("mobile_ip_list", ["127.0.0.1"])),
                    correlation_id=correlation_id,
                    metadata=metadata,
                )
                if orchestrator is not None:
                    orchestrator.handle_connection_config(connection_config)
                    orchestrator.handle_trust_handshake_received(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                else:
                    session_registry.bootstrap(connection_config)
                _logger.info(
                    "Instant-share session bootstrapped from handshake: session_id=%s",
                    session_id,
                )
            except Exception as exc:
                _logger.warning(
                    "Failed to bootstrap instant-share session from handshake: %s",
                    exc,
                )

        try:
            trust_session.store_mobile_handshake(
                mobile_dh_public_key=str(mobile_dh_public_key),
                mobile_nonce=str(mobile_nonce),
            )
            trust_session.establish_session_key()
            response = trust_session.handshake_response()
            _logger.info(
                "Trust handshake completed: session_id=%s correlation_id=%s",
                session_id,
                correlation_id,
            )
            self._send_json(200, response)
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _handle_trust_apply(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        if trust_registry is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "Trust service not initialized"})
            return
        session_id = self.headers.get("X-Session-Id", "")
        correlation_id = self.headers.get("X-Correlation-Id", "")
        try:
            trust_session = trust_registry.require_session(session_id)
        except InstantShareError:
            self._send_json(400, {"error_code": "HANDSHAKE_REQUIRED", "message": "No active session found"})
            return
        if not trust_session.is_session_key_established:
            self._send_json(400, {"error_code": "HANDSHAKE_REQUIRED", "message": "Session key not established. Complete handshake first."})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            envelope = json.loads(raw_body.decode("utf-8"))
        except Exception:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Invalid JSON body"})
            return
        if not isinstance(envelope, dict):
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Request body must be a JSON object"})
            return
        try:
            decrypted = trust_session.decrypt_apply_request(envelope)
            action = decrypted.get("action")
            if action != "request_pin":
                self._send_json(400, {"error_code": "INVALID_REQUEST", "message": f"Unsupported action: {action}"})
                return
            pin = trust_session.generate_pin()
            pin_envelope = trust_session.encrypted_pin_envelope()
            if self.__class__.pin_display_callback is not None:
                self.__class__.pin_display_callback(pin)
            _logger.info(
                "Trust apply completed: session_id=%s pin=%s",
                session_id,
                pin,
            )
            response = {"apply_status": "accepted", **pin_envelope}
            self._send_json(202, response)
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _handle_trust_confirm(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        if trust_registry is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "Trust service not initialized"})
            return
        session_id = self.headers.get("X-Session-Id", "")
        correlation_id = self.headers.get("X-Correlation-Id", "")
        try:
            trust_session = trust_registry.require_session(session_id)
        except InstantShareError:
            self._send_json(400, {"error_code": "HANDSHAKE_REQUIRED", "message": "No active session found"})
            return
        if not trust_session.is_session_key_established:
            self._send_json(400, {"error_code": "HANDSHAKE_REQUIRED", "message": "Session key not established. Complete handshake first."})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            envelope = json.loads(raw_body.decode("utf-8"))
        except Exception:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Invalid JSON body"})
            return
        if not isinstance(envelope, dict):
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Request body must be a JSON object"})
            return
        try:
            decrypted = trust_session.decrypt_confirm_request(envelope)
            action = decrypted.get("action")
            if action != "confirm":
                self._send_json(400, {"error_code": "INVALID_REQUEST", "message": f"Unsupported action: {action}"})
                return
            trust_session.mark_trusted()
            trust_status_envelope = trust_session.encrypted_trust_status()
            _logger.info(
                "Trust confirmed: session_id=%s correlation_id=%s",
                session_id,
                correlation_id,
            )
            self._send_json(200, trust_status_envelope)
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _handle_transfer_text(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        transfer_handler = self.__class__.transfer_handler
        session_registry = self.__class__.session_registry
        orchestrator = self.__class__.orchestrator
        if trust_registry is None or transfer_handler is None or session_registry is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "Transfer service not initialized"})
            return
        session_id = self.headers.get("X-Session-Id", "")
        correlation_id = self.headers.get("X-Correlation-Id", "")
        trust_session = trust_registry.get_session(session_id)
        if trust_session is None:
            self._send_json(404, {"error_code": "SESSION_NOT_FOUND", "message": "No active session found"})
            return
        if not trust_session.is_trusted:
            self._send_json(403, {"error_code": "TRUST_REQUIRED", "message": "Trust handshake must be completed before transfer"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            result = transfer_handler.receive_text(
                session_id=session_id,
                correlation_id=correlation_id,
                body=raw_body,
            )
            _logger.info(
                "Transfer text received: session_id=%s correlation_id=%s",
                session_id,
                correlation_id,
            )
            if orchestrator is not None:
                try:
                    orchestrator.handle_transfer_received(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                    orchestrator.handle_delivery_complete(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                except Exception as exc:
                    _logger.warning("Failed to publish transfer lifecycle event: %s", exc)
            self._send_json(200, {"state": "delivered", **result.as_dict()})
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _handle_transfer_image(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        transfer_handler = self.__class__.transfer_handler
        session_registry = self.__class__.session_registry
        orchestrator = self.__class__.orchestrator
        if trust_registry is None or transfer_handler is None or session_registry is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "Transfer service not initialized"})
            return
        session_id = self.headers.get("X-Session-Id", "")
        correlation_id = self.headers.get("X-Correlation-Id", "")
        content_type = self.headers.get("Content-Type", "application/octet-stream")
        filename = self.headers.get("X-Instant-Share-Filename")
        trust_session = trust_registry.get_session(session_id)
        if trust_session is None:
            self._send_json(404, {"error_code": "SESSION_NOT_FOUND", "message": "No active session found"})
            return
        if not trust_session.is_trusted:
            self._send_json(403, {"error_code": "TRUST_REQUIRED", "message": "Trust handshake must be completed before transfer"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b""
            result = transfer_handler.receive_image(
                session_id=session_id,
                correlation_id=correlation_id,
                body=raw_body,
                content_type=content_type,
                filename=filename,
            )
            _logger.info(
                "Transfer image received: session_id=%s correlation_id=%s",
                session_id,
                correlation_id,
            )
            if orchestrator is not None:
                try:
                    orchestrator.handle_transfer_received(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                    orchestrator.handle_delivery_complete(
                        session_id=session_id,
                        correlation_id=correlation_id,
                    )
                except Exception as exc:
                    _logger.warning("Failed to publish transfer lifecycle event: %s", exc)
            self._send_json(200, {"state": "delivered", **result.as_dict()})
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _send_json(self, status: int, body: dict) -> None:
        resp = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)


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
    ) -> None:
        self._host = host
        self._port = port
        self._on_error = on_error
        self._trust_session_registry = trust_session_registry
        self._session_registry = session_registry
        self._orchestrator = orchestrator
        self._transfer_handler = transfer_handler
        self._pin_display_callback = pin_display_callback
        self._http_server: HTTPServer | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.RLock()

    @property
    def is_running(self) -> bool:
        with self._lock:
            return self._thread is not None and self._thread.is_alive()

    @property
    def port(self) -> int:
        return self._port

    def start(self) -> bool:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return True
            self._stop_event = threading.Event()
            _InstantShareHandler.on_error = self._on_error
            _InstantShareHandler.trust_session_registry = self._trust_session_registry
            _InstantShareHandler.session_registry = self._session_registry
            _InstantShareHandler.orchestrator = self._orchestrator
            _InstantShareHandler.transfer_handler = self._transfer_handler
            _InstantShareHandler.pin_display_callback = self._pin_display_callback
            try:
                self._http_server = HTTPServer((self._host, self._port), _InstantShareHandler)
            except OSError as exc:
                _logger.error("Failed to bind instant-share HTTP server: %s", exc)
                return False
            self._thread = threading.Thread(
                target=self._http_server.serve_forever,
                name="instant_share_http",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info(
            "Instant-share HTTP server started on %s:%d",
            self._host,
            self._port,
        )
        return True

    def stop(self) -> None:
        with self._lock:
            thread = self._thread
            self._thread = None
            http_server = self._http_server
            self._http_server = None
        if http_server is not None:
            http_server.shutdown()
        if thread is not None:
            thread.join(timeout=5.0)
        _InstantShareHandler.on_error = None
        _InstantShareHandler.trust_session_registry = None
        _InstantShareHandler.session_registry = None
        _InstantShareHandler.orchestrator = None
        _InstantShareHandler.transfer_handler = None
        _InstantShareHandler.pin_display_callback = None
        _logger.info("Instant-share HTTP server stopped")