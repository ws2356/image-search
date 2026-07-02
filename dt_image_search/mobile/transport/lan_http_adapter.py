from __future__ import annotations

from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import errno
import json
import threading
from typing import Callable
from urllib.parse import parse_qs, urlparse

from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
    TRANSFER_ASSET_STREAM_STATE_CHUNK,
    TRANSFER_ASSET_STREAM_STATE_COMPLETE,
    TRANSFER_ASSET_STREAM_STATE_FIELD,
    TRANSFER_ASSET_STREAM_STATE_START,
    TransferAssetUploadStream,
)
from dt_image_search.mobile.mobile_payload_encryption import (
    MOBILE_ENCRYPTED_BINARY_CHUNK_OVERHEAD_BYTES,
    MobilePayloadEncryptionError,
    decrypt_mobile_binary_chunk,
    decrypt_mobile_json_payload,
    encrypt_mobile_json_payload,
    is_mobile_encrypted_payload,
)
from dt_image_search.mobile.transport.contracts import (
    CAPABILITY_EXCHANGE_OPERATION,
    PAIRING_CLAIM_OPERATION,
    PAIRING_STATE_OPERATION,
    TRANSFER_ASSET_OPERATION,
    TRANSFER_COMPLETE_OPERATION,
    TRANSFER_EXISTENCE_OPERATION,
    TRANSFER_START_OPERATION,
    UPDATE_PROMPT_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
)
from dt_image_search.mobile.transport.router import MobileTransportRouter


class _LanHttpServer(ThreadingHTTPServer):
    daemon_threads = True


@dataclass(frozen=True)
class LanHttpEndpointInfo:
    endpoint_url: str
    endpoint_urls: tuple[str, ...]


def is_ignorable_socket_disconnect(exc: BaseException) -> bool:
    if isinstance(exc, (BrokenPipeError, ConnectionResetError)):
        return True
    return isinstance(exc, OSError) and exc.errno in {
        errno.EPIPE,
        errno.ECONNABORTED,
        errno.ECONNRESET,
        errno.ENOTCONN,
    }


class LanHttpTransportAdapter:
    def __init__(
        self,
        *,
        listen_host: str,
        advertised_host: str | None,
        router: MobileTransportRouter,
        resolve_advertised_hosts: Callable[[str | None], tuple[str, ...]],
        format_pairing_endpoint_url: Callable[[str, int], str],
        pairing_claim_path: str,
        pairing_state_path: str,
        pairing_protocol_schema: str,
        pairing_rejected_status: str,
        transfer_schema: str,
        capability_exchange_schema: str,
        capability_exchange_path: str,
        update_prompt_schema: str,
        update_prompt_path: str,
        transfer_start_path: str,
        transfer_existence_path: str,
        transfer_asset_path: str,
        transfer_complete_path: str,
        log_handler: Callable[..., None],
        resolve_transfer_trust_key: Callable[..., str | None] | None = None,
        handle_transfer_asset_stream_error: Callable[[dict[str, object] | None, OSError], tuple[int, dict[str, object]]] | None = None,
    ):
        self._listen_host = listen_host
        self._advertised_host = advertised_host
        self._router = router
        self._resolve_advertised_hosts = resolve_advertised_hosts
        self._format_pairing_endpoint_url = format_pairing_endpoint_url
        self._pairing_claim_path = pairing_claim_path
        self._pairing_state_path = pairing_state_path
        self._pairing_protocol_schema = pairing_protocol_schema
        self._pairing_rejected_status = pairing_rejected_status
        self._transfer_schema = transfer_schema
        self._capability_exchange_schema = capability_exchange_schema
        self._capability_exchange_path = capability_exchange_path
        self._update_prompt_schema = update_prompt_schema
        self._update_prompt_path = update_prompt_path
        self._transfer_start_path = transfer_start_path
        self._transfer_existence_path = transfer_existence_path
        self._transfer_asset_path = transfer_asset_path
        self._transfer_complete_path = transfer_complete_path
        self._log_handler = log_handler
        self._resolve_transfer_trust_key = resolve_transfer_trust_key
        self._handle_transfer_asset_stream_error = handle_transfer_asset_stream_error

        self._lock = threading.RLock()
        self._asset_upload_stream = TransferAssetUploadStream()
        self._server: _LanHttpServer | None = None
        self._server_thread: threading.Thread | None = None
        self._endpoint_info: LanHttpEndpointInfo | None = None

    def start(self) -> LanHttpEndpointInfo:
        with self._lock:
            if self._endpoint_info is not None and self._server is not None:
                return self._endpoint_info

            handler_class = self._build_handler()
            self._server = _LanHttpServer((self._listen_host, 0), handler_class)
            port = self._server.server_address[1]
            advertised_hosts = self._resolve_advertised_hosts(self._advertised_host)
            endpoint_urls = tuple(
                self._format_pairing_endpoint_url(host, port)
                for host in advertised_hosts
            )
            endpoint_info = LanHttpEndpointInfo(
                endpoint_url=endpoint_urls[0],
                endpoint_urls=endpoint_urls,
            )
            self._endpoint_info = endpoint_info
            self._server_thread = threading.Thread(
                target=self._server.serve_forever,
                name="mobile-pairing-bootstrap",
                daemon=True,
            )
            self._server_thread.start()
            self._safe_log(
                "info",
                message=(
                    "MobilePairingService/_ensure_server_started: listening for pairing requests on "
                    f"{endpoint_info.endpoint_url} "
                    f"(listen_host={self._listen_host} bound_address={self._server.server_address[0]} "
                    f"bound_port={port} advertised_hosts={advertised_hosts} "
                    f"advertised_endpoints={endpoint_urls})"
                ),
            )
            return endpoint_info

    def stop(self) -> None:
        server_to_stop: _LanHttpServer | None
        with self._lock:
            server_to_stop = self._server
            self._server = None
            self._server_thread = None
            self._endpoint_info = None
            self._asset_upload_stream.clear()

        if server_to_stop is not None:
            server_to_stop.shutdown()
            server_to_stop.server_close()

    def _build_handler(self) -> type[BaseHTTPRequestHandler]:
        adapter = self

        class PairingHandler(BaseHTTPRequestHandler):
            def handle_one_request(self) -> None:
                try:
                    super().handle_one_request()
                except OSError as exc:
                    if not is_ignorable_socket_disconnect(exc):
                        raise
                    self.close_connection = True
                    adapter._safe_log(
                        "debug",
                        message=(
                            "MobilePairingService/http: ignoring disconnected client during HTTP request handling "
                            f"from {self.client_address}: {exc}"
                        ),
                    )

            def do_POST(self) -> None:
                try:
                    parsed_path = urlparse(self.path)
                    if parsed_path.path == adapter._pairing_claim_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._pairing_protocol_schema,
                            status=adapter._pairing_rejected_status,
                            state_field="backup_state",
                            parse_error_message="Desktop could not parse the pairing request JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for pairing requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(PAIRING_CLAIM_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._pairing_state_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._pairing_protocol_schema,
                            status=adapter._pairing_rejected_status,
                            state_field="backup_state",
                            parse_error_message="Desktop could not parse the pairing state JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for pairing state requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(PAIRING_STATE_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._transfer_start_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._transfer_schema,
                            status="rejected",
                            parse_error_message="Desktop could not parse the transfer request JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for transfer requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(TRANSFER_START_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._transfer_existence_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._transfer_schema,
                            status="rejected",
                            parse_error_message="Desktop could not parse the transfer existence JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for transfer existence requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(TRANSFER_EXISTENCE_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._transfer_complete_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._transfer_schema,
                            status="rejected",
                            parse_error_message="Desktop could not parse the transfer completion JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for transfer completion requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(TRANSFER_COMPLETE_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._capability_exchange_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._capability_exchange_schema,
                            status="rejected",
                            parse_error_message="Desktop could not parse the capability exchange JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for capability exchange requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(CAPABILITY_EXCHANGE_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._update_prompt_path:
                        request_payload = self._read_json_payload(
                            schema=adapter._update_prompt_schema,
                            status="rejected",
                            parse_error_message="Desktop could not parse the update prompt JSON payload.",
                            object_error_message="Desktop requires JSON object payloads for update prompt requests.",
                        )
                        if request_payload is None:
                            return
                        self._dispatch_operation(UPDATE_PROMPT_OPERATION, request_payload)
                        return

                    if parsed_path.path == adapter._transfer_asset_path:
                        query_parameters = parse_qs(parsed_path.query, keep_blank_values=False)
                        request_id = query_parameters.get("request_id", [None])[0]
                        if not isinstance(request_id, str) or not request_id.strip():
                            self._write_json_response(
                                400,
                                {
                                    "schema": adapter._transfer_schema,
                                    "status": "rejected",
                                    "message": "Desktop did not receive a transfer asset request id.",
                                },
                            )
                            return
                        request_id = request_id.strip()

                        stream_state = query_parameters.get(TRANSFER_ASSET_STREAM_STATE_FIELD, [None])[0]
                        if stream_state == TRANSFER_ASSET_STREAM_STATE_START:
                            request_payload = self._read_json_payload(
                                schema=adapter._transfer_schema,
                                status="rejected",
                                parse_error_message="Desktop could not parse the transfer asset stream start payload.",
                                object_error_message=(
                                    "Desktop requires JSON object payloads for transfer asset stream start requests."
                                ),
                            )
                            if request_payload is None:
                                return
                            metadata_payload = dict(request_payload)
                            metadata_payload.pop(TRANSFER_ASSET_STREAM_STATE_FIELD, None)
                            metadata_payload.pop("chunk_size", None)
                            encrypted_chunk_trust_key: str | None = None
                            if is_mobile_encrypted_payload(metadata_payload):
                                (
                                    metadata_payload,
                                    encrypted_chunk_trust_key,
                                    decrypt_error_message,
                                ) = adapter._decrypt_transfer_asset_stream_metadata(
                                    metadata_payload
                                )
                                if decrypt_error_message is not None:
                                    self._write_json_response(
                                        400,
                                        {
                                            "schema": adapter._transfer_schema,
                                            "status": "rejected",
                                            "message": decrypt_error_message,
                                        },
                                    )
                                    return
                            try:
                                with adapter._lock:
                                    adapter._asset_upload_stream.start(
                                        request_id=request_id,
                                        metadata_payload=metadata_payload,
                                        encryption_trust_key_b64=encrypted_chunk_trust_key,
                                    )
                            except OSError as exc:
                                self._write_transfer_asset_stream_error_response(
                                    request_id=None,
                                    metadata_payload=metadata_payload,
                                    error=exc,
                                    encryption_trust_key_b64=encrypted_chunk_trust_key,
                                )
                                return
                            self._write_json_response(
                                200,
                                {
                                    "schema": adapter._transfer_schema,
                                    "status": "accepted",
                                    "message": "Desktop accepted transfer asset stream metadata.",
                                    "request_id": request_id,
                                },
                                encryption_trust_key_b64=encrypted_chunk_trust_key,
                                encryption_locator_fields=self._transfer_response_locator_fields(
                                    metadata_payload
                                ),
                            )
                            return

                        if stream_state == TRANSFER_ASSET_STREAM_STATE_CHUNK:
                            try:
                                content_length = int(self.headers.get("Content-Length", "0"))
                            except ValueError:
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": "Desktop received an invalid transfer asset stream chunk length.",
                                    },
                                )
                                return
                            if content_length <= 0:
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": "Desktop received an invalid transfer asset stream chunk length.",
                                    },
                                )
                                return
                            if content_length > (
                                TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES
                                + MOBILE_ENCRYPTED_BINARY_CHUNK_OVERHEAD_BYTES
                            ):
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": (
                                            "Desktop rejected transfer asset stream chunk because "
                                            f"it exceeded {TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES} bytes."
                                        ),
                                    },
                                )
                                return
                            try:
                                chunk = self.rfile.read(content_length)
                            except OSError as exc:
                                self._write_transfer_asset_stream_error_response(
                                    request_id=request_id,
                                    metadata_payload=None,
                                    error=exc,
                                    encryption_trust_key_b64=None,
                                )
                                return
                            if len(chunk) != content_length:
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": "Desktop received an incomplete transfer asset stream chunk.",
                                    },
                                )
                                return
                            try:
                                encrypted_chunk_response_locators: dict[str, str] | None = None
                                with adapter._lock:
                                    encrypted_chunk_trust_key = adapter._asset_upload_stream.encryption_trust_key(
                                        request_id=request_id,
                                    )
                                    encrypted_chunk_response_locators = self._transfer_response_locator_fields(
                                        adapter._asset_upload_stream.metadata_payload(request_id=request_id)
                                    )
                                if encrypted_chunk_trust_key is not None:
                                    chunk = decrypt_mobile_binary_chunk(
                                        encrypted_chunk=chunk,
                                        trust_key_b64=encrypted_chunk_trust_key,
                                    )
                            except MobilePayloadEncryptionError as exc:
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": str(exc),
                                    },
                                    encryption_trust_key_b64=encrypted_chunk_trust_key,
                                    encryption_locator_fields=encrypted_chunk_response_locators,
                                )
                                return
                            append_error = None
                            try:
                                with adapter._lock:
                                    append_error = adapter._asset_upload_stream.append_chunk(
                                        chunk=chunk,
                                        request_id=request_id,
                                    )
                            except OSError as exc:
                                self._write_transfer_asset_stream_error_response(
                                    request_id=request_id,
                                    metadata_payload=None,
                                    error=exc,
                                    encryption_trust_key_b64=encrypted_chunk_trust_key,
                                )
                                return
                            if append_error is not None:
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": append_error,
                                    },
                                    encryption_trust_key_b64=encrypted_chunk_trust_key,
                                    encryption_locator_fields=encrypted_chunk_response_locators,
                                )
                                return
                            self._write_json_response(
                                200,
                                {
                                    "schema": adapter._transfer_schema,
                                    "status": "accepted",
                                    "message": "Desktop accepted transfer asset stream chunk.",
                                    "request_id": request_id,
                                },
                                encryption_trust_key_b64=encrypted_chunk_trust_key,
                                encryption_locator_fields=encrypted_chunk_response_locators,
                            )
                            return

                        if stream_state == TRANSFER_ASSET_STREAM_STATE_COMPLETE:
                            try:
                                with adapter._lock:
                                    payload_or_error = adapter._asset_upload_stream.complete(
                                        request_id=request_id,
                                    )
                            except OSError as exc:
                                self._write_transfer_asset_stream_error_response(
                                    request_id=request_id,
                                    metadata_payload=None,
                                    error=exc,
                                    encryption_trust_key_b64=None,
                                )
                                return
                            if isinstance(payload_or_error, str):
                                self._write_json_response(
                                    400,
                                    {
                                        "schema": adapter._transfer_schema,
                                        "status": "rejected",
                                        "message": payload_or_error,
                                    },
                                )
                                return
                            self._dispatch_operation(
                                TRANSFER_ASSET_OPERATION,
                                payload_or_error,
                            )
                            return

                        self._write_json_response(
                            400,
                            {
                                "schema": adapter._transfer_schema,
                                "status": "rejected",
                                "message": (
                                    "Desktop rejected transfer asset stream request with an unsupported "
                                    f"'{TRANSFER_ASSET_STREAM_STATE_FIELD}' value."
                                ),
                            },
                        )
                        return

                    self._write_json_response(
                        404,
                        {
                            "schema": adapter._pairing_protocol_schema,
                            "backup_state": adapter._pairing_rejected_status,
                            "message": "Unknown pairing endpoint.",
                        },
                    )
                except Exception as exc:
                    adapter._safe_log(
                        "error",
                        error_type=type(exc).__name__,
                        where="mobile_pairing_service.PairingHandler.do_POST",
                        message=f"Unhandled pairing request error: {exc}",
                    )
                    if not self.wfile.closed:
                        self._write_json_response(
                            500,
                            {
                                "schema": adapter._pairing_protocol_schema,
                                "backup_state": adapter._pairing_rejected_status,
                                "message": (
                                    "Desktop failed while processing the pairing request. "
                                    "Retry pairing and check desktop logs if the issue persists."
                                ),
                            },
                        )

            def log_message(self, format: str, *args: object) -> None:
                adapter._safe_log("debug", message=f"MobilePairingService/http: {format % args}")

            def _dispatch_operation(self, operation: str, payload: object) -> None:
                context = adapter._build_context(operation=operation, client_address=self.client_address)
                response = adapter._router.dispatch(
                    operation=operation,
                    payload=payload,
                    context=context,
                )
                self._write_json_response(response.status_code, response.payload)

            def _write_transfer_asset_stream_error_response(
                self,
                *,
                request_id: str | None,
                metadata_payload: dict[str, object] | None,
                error: OSError,
                encryption_trust_key_b64: str | None = None,
            ) -> None:
                if request_id is not None:
                    with adapter._lock:
                        if encryption_trust_key_b64 is None:
                            encryption_trust_key_b64 = adapter._asset_upload_stream.encryption_trust_key(
                                request_id=request_id
                            )
                        discarded_payload = adapter._asset_upload_stream.discard(request_id=request_id)
                    if metadata_payload is None:
                        metadata_payload = discarded_payload
                if adapter._handle_transfer_asset_stream_error is None:
                    raise error
                status_code, response_payload = adapter._handle_transfer_asset_stream_error(
                    metadata_payload=metadata_payload,
                    error=error,
                )
                locator_fields = self._transfer_response_locator_fields(metadata_payload)
                self._write_json_response(
                    status_code,
                    response_payload,
                    encryption_trust_key_b64=encryption_trust_key_b64,
                    encryption_locator_fields=locator_fields,
                )

            def _read_json_payload(
                self,
                *,
                schema: str,
                status: str,
                state_field: str = "status",
                parse_error_message: str,
                object_error_message: str,
            ) -> dict[str, object] | None:
                content_length = int(self.headers.get("Content-Length", "0"))
                raw_payload = self.rfile.read(content_length)
                try:
                    request_payload = json.loads(raw_payload.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    self._write_json_response(
                        400,
                        {
                            "schema": schema,
                            state_field: status,
                            "message": parse_error_message,
                        },
                    )
                    return None

                if not isinstance(request_payload, dict):
                    self._write_json_response(
                        400,
                        {
                            "schema": schema,
                            state_field: status,
                            "message": object_error_message,
                        },
                    )
                    return None
                return request_payload

            def _write_json_response(
                self,
                status_code: int,
                payload: dict[str, object],
                *,
                encryption_trust_key_b64: str | None = None,
                encryption_locator_fields: dict[str, str] | None = None,
            ) -> None:
                encoded_payload = payload
                if encryption_trust_key_b64 is not None:
                    if not encryption_locator_fields:
                        status_code = 500
                        encoded_payload = {
                            "schema": adapter._transfer_schema,
                            "status": "rejected",
                            "message": "Desktop could not build encrypted response locators.",
                        }
                    else:
                        try:
                            encoded_payload = encrypt_mobile_json_payload(
                                payload=payload,
                                trust_key_b64=encryption_trust_key_b64,
                                locator_fields=encryption_locator_fields,
                            )
                        except MobilePayloadEncryptionError as exc:
                            status_code = 500
                            encoded_payload = {
                                "schema": adapter._transfer_schema,
                                "status": "rejected",
                                "message": str(exc),
                            }
                encoded_body = json.dumps(
                    encoded_payload,
                    separators=(",", ":"),
                    sort_keys=True,
                ).encode("utf-8")
                self.close_connection = True
                self.send_response(status_code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Connection", "close")
                self.send_header("Content-Length", str(len(encoded_body)))
                self.end_headers()
                self.wfile.write(encoded_body)

            @staticmethod
            def _transfer_response_locator_fields(
                metadata_payload: dict[str, object] | None,
            ) -> dict[str, str] | None:
                if metadata_payload is None:
                    return None
                session_id = metadata_payload.get("session_id")
                if not isinstance(session_id, str) or not session_id.strip():
                    return None
                return {
                    "session_id": session_id.strip(),
                }

        return PairingHandler

    def _build_context(
        self,
        *,
        operation: str,
        client_address: tuple[str, int] | str | None,
    ) -> MobileTransportContext:
        remote_address: str | None = None
        if isinstance(client_address, tuple) and len(client_address) >= 2:
            remote_address = f"{client_address[0]}:{client_address[1]}"
        elif isinstance(client_address, str):
            remote_address = client_address
        return MobileTransportContext(
            transport=MobileTransportKind.LAN_HTTP,
            operation=operation,
            remote_address=remote_address,
        )

    def _decrypt_transfer_asset_stream_metadata(
        self,
        metadata_payload: dict[str, object],
    ) -> tuple[dict[str, object], str | None, str | None]:
        if self._resolve_transfer_trust_key is None:
            return (
                metadata_payload,
                None,
                "Desktop does not support encrypted transfer asset metadata requests.",
            )
        session_id = metadata_payload.get("session_id")
        if not isinstance(session_id, str) or not session_id.strip():
            return (
                metadata_payload,
                None,
                "Desktop rejected encrypted transfer asset metadata field 'session_id'.",
            )
        trust_key_b64 = self._resolve_transfer_trust_key(
            session_id=session_id.strip(),
        )
        if trust_key_b64 is None:
            return (
                metadata_payload,
                None,
                "Desktop rejected the transfer session.",
            )
        try:
            decrypted_payload = decrypt_mobile_json_payload(
                encrypted_payload=metadata_payload,
                trust_key_b64=trust_key_b64,
            )
        except MobilePayloadEncryptionError as exc:
            return metadata_payload, None, str(exc)
        return decrypted_payload, trust_key_b64, None

    def _safe_log(
        self,
        severity: str,
        *,
        message: str,
        error_type: str = "",
        where: str = "",
    ) -> None:
        try:
            self._log_handler(
                severity,
                error_type=error_type,
                where=where,
                message=message,
            )
        except Exception:
            return
