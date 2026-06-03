from __future__ import annotations

import json
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Callable

from dt_image_search.instant_sharing.contracts import API_PREFIX
from dt_image_search.instant_sharing.mdns import BootstrapRequest, ConnectionConfig, InstantShareBleService


_logger = logging.getLogger(__name__)

BOOTSTRAP_PATH = f"{API_PREFIX}/sessions/bootstrap"


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


class _BootstrapHandler(BaseHTTPRequestHandler):
    ble_service: InstantShareBleService | None = None
    on_error: Callable[[str], None] | None = None

    def log_message(self, format: str, *args: object) -> None:
        _logger.debug("BootstrapHTTPServer: " + format % args)

    def do_POST(self) -> None:
        if self.path != BOOTSTRAP_PATH:
            self._send_json(404, {"error_code": "NOT_FOUND", "message": "Unknown endpoint"})
            return
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
    ) -> None:
        self._ble_service = ble_service
        self._host = host
        self._port = port
        self._on_error = on_error
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
            _BootstrapHandler.ble_service = self._ble_service
            _BootstrapHandler.on_error = self._on_error
            try:
                self._http_server = HTTPServer((self._host, self._port), _BootstrapHandler)
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
        _BootstrapHandler.ble_service = None
        _BootstrapHandler.on_error = None
        _logger.info("Bootstrap HTTP server stopped")
