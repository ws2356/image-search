from __future__ import annotations

import json
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Callable

from dt_image_search.instant_sharing.contracts import (
    API_PREFIX,
    TRUST_HANDSHAKE_PATH,
    TRUST_APPLY_PATH,
    TRUST_CONFIRM_PATH,
    TRANSFER_TEXT_PATH,
    TRANSFER_IMAGE_PATH,
    BOOTSTRAP_PATH,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.mdns import BootstrapRequest, ConnectionConfig, InstantShareBleService
from dt_image_search.instant_sharing.trust_server import TrustSession, TrustSessionRegistry
from dt_image_search.instant_sharing.transfer_server import TransferHandler
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


_logger = logging.getLogger(__name__)


def _bootstrap_request_to_connection_config(req: BootstrapRequest) -> ConnectionConfig:
    from dt_image_search.instant_sharing.contracts import InstantShareMetadata, PayloadClass, TargetIntent, TrustMode

    metadata = InstantShareMetadata(
        flow_id="instant_share",
        payload_class=PayloadClass(req.payload_class),
        target_intent=TargetIntent(req.target_intent),
        trust_mode=TrustMode.FIRST_SHARE,
    )
    return ConnectionConfig(
        session_id=req.session_id,
        mobile_port=req.mobile_port,
        mobile_ip_list=req.mobile_ip_list,
        correlation_id=req.correlation_id,
        metadata=metadata,
    )


class _InstantShareHandler(BaseHTTPRequestHandler):
    ble_service: InstantShareBleService | None = None
    on_error: Callable[[str], None] | None = None
    trust_session_registry: TrustSessionRegistry | None = None
    session_registry: InstantShareSessionRegistry | None = None
    transfer_handler: TransferHandler | None = None
    pin_display_callback: Callable[[str], None] | None = None

    def log_message(self, format: str, *args: object) -> None:
        _logger.debug("InstantShareHTTPServer: " + format % args)

    def do_POST(self) -> None:
        if self.path == BOOTSTRAP_PATH:
            self._handle_bootstrap()
        elif self.path == TRUST_HANDSHAKE_PATH:
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

    def _handle_bootstrap(self) -> None:
        service = self.__class__.ble_service
        if service is None:
            self._send_json(503, {"error_code": "SERVICE_UNAVAILABLE", "message": "BLE service not initialized"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            payload: object = json.loads(raw_body.decode("utf-8"))
        except Exception:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Invalid JSON body"})
            return
        if not isinstance(payload, dict):
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Request body must be a JSON object"})
            return
        try:
            bootstrap_req = BootstrapRequest.from_dict(payload)
        except Exception as e:
            self._send_json(400, {"error_code": "INVALID_BOOTSTRAP", "message": str(e)})
            if self.__class__.on_error:
                self.__class__.on_error(f"Bootstrap validation error: {e}")
            return
        try:
            connection_config = _bootstrap_request_to_connection_config(bootstrap_req)
            service.handle_bootstrap(connection_config)
        except Exception as e:
            self._send_json(
                409,
                {"error_code": "RECEIVER_BUSY_SINGLE_SESSION", "message": str(e)},
            )
            if self.__class__.on_error:
                self.__class__.on_error(f"Bootstrap handler error: {e}")
            return
        trust_registry = self.__class__.trust_session_registry
        if trust_registry is not None:
            try:
                trust_registry.create_session(
                    session_id=connection_config.session_id,
                    correlation_id=connection_config.correlation_id,
                )
            except Exception:
                _logger.debug("Trust session already exists for session_id=%s", connection_config.session_id)
        device_id = ""
        try:
            name_adv = service.read_characteristic("DeviceName")
            device_id = str(name_adv.get("receiver_id", ""))
        except Exception:
            pass
        self._send_json(200, {"accepted": True, "pc_device_id": device_id})
        _logger.info(
            "Bootstrap accepted: session_id=%s correlation_id=%s",
            bootstrap_req.session_id,
            bootstrap_req.correlation_id,
        )

    def _handle_trust_handshake(self) -> None:
        trust_registry = self.__class__.trust_session_registry
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
        try:
            trust_session = trust_registry.require_session(session_id)
        except InstantShareError:
            self._send_json(400, {"error_code": "HANDSHAKE_REQUIRED", "message": "No active session found for the provided session_id"})
            return
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
            self._send_json(200, {"state": "delivered", **result.as_dict()})
        except InstantShareError as e:
            self._send_json(400, {"error_code": e.error_code.value, "message": e.message})

    def _handle_transfer_image(self) -> None:
        trust_registry = self.__class__.trust_session_registry
        transfer_handler = self.__class__.transfer_handler
        session_registry = self.__class__.session_registry
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


class InstantShareBootstrapServer:
    def __init__(
        self,
        *,
        ble_service: InstantShareBleService,
        host: str = "0.0.0.0",
        port: int = 9527,
        on_error: Callable[[str], None] | None = None,
        trust_session_registry: TrustSessionRegistry | None = None,
        session_registry: InstantShareSessionRegistry | None = None,
        transfer_handler: TransferHandler | None = None,
        pin_display_callback: Callable[[str], None] | None = None,
    ) -> None:
        self._ble_service = ble_service
        self._host = host
        self._port = port
        self._on_error = on_error
        self._trust_session_registry = trust_session_registry
        self._session_registry = session_registry
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
            _InstantShareHandler.ble_service = self._ble_service
            _InstantShareHandler.on_error = self._on_error
            _InstantShareHandler.trust_session_registry = self._trust_session_registry
            _InstantShareHandler.session_registry = self._session_registry
            _InstantShareHandler.transfer_handler = self._transfer_handler
            _InstantShareHandler.pin_display_callback = self._pin_display_callback
            try:
                self._http_server = HTTPServer((self._host, self._port), _InstantShareHandler)
            except OSError as exc:
                _logger.error("Failed to bind bootstrap HTTP server: %s", exc)
                return False
            self._thread = threading.Thread(
                target=self._http_server.serve_forever,
                name="instant_share_bootstrap_http",
                daemon=True,
            )
            thread = self._thread
        thread.start()
        _logger.info(
            "Bootstrap HTTP server started on %s:%d",
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
        _InstantShareHandler.ble_service = None
        _InstantShareHandler.on_error = None
        _InstantShareHandler.trust_session_registry = None
        _InstantShareHandler.session_registry = None
        _InstantShareHandler.transfer_handler = None
        _InstantShareHandler.pin_display_callback = None
        _logger.info("Bootstrap HTTP server stopped")