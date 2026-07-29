#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AOA USB transport adapter for the desktop AuBackup companion.

The adapter polls for Android devices in AOA accessory mode (or capable of
entering it), performs a challenge/response auth handshake, then routes
``dtis.mobile-transport.v1`` envelopes to the shared ``MobileTransportRouter``.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import threading
import time
from typing import Callable

from dt_image_search.mobile.transport.aoa_frame_codec import (
    AOA_FRAME_FLAG_BINARY,
    AOA_FRAME_FLAG_TEXT,
    AOA_REQUEST_ID_LENGTH,
    AoaFrameDecoder,
    AoaFrameError,
    encode_aoa_frame,
)
from dt_image_search.mobile.transport.aoa_host_driver import (
    AoaDetectedDevice,
    AoaHostDriver,
    AoaHostState,
    AoaReadStream,
    AoaWriteStream,
    PyUsbAoaHostDriver,
    SimulatedAoaHostDriver,
)
from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
    TRANSFER_ASSET_STREAM_STATE_COMPLETE,
    TRANSFER_ASSET_STREAM_STATE_FIELD,
    TRANSFER_ASSET_STREAM_STATE_START,
    TransferAssetUploadStream,
)
from dt_image_search.mobile.mobile_payload_encryption import (
    MobilePayloadEncryptionError,
    decrypt_mobile_binary_chunk,
    decrypt_mobile_json_payload,
    is_mobile_encrypted_payload,
)
from dt_image_search.mobile.transport.contracts import (
    TRANSFER_ASSET_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
    MobileTransportResponse,
    TransferAssetUploadPayload,
)
from dt_image_search.mobile.transport.router import (
    MobileTransportRouteNotFoundError,
    MobileTransportRouter,
)
from dt_image_search.mobile.transport.usb_ws_adapter import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    USB_AUTH_CHALLENGE_BODY_SCHEMA,
    USB_AUTH_CHALLENGE_OPERATION,
    USB_AUTH_CHALLENGE_REQUEST_ID,
    USB_AUTH_CHALLENGE_TIMEOUT_SECONDS,
    USB_TRANSPORT_REJECTED_STATUS,
    UsbBootstrapConfig,
    UsbTransportState,
)
from dt_image_search.telemetry.telemetry_client import log

# AOA binary asset chunks reuse the same header layout as the outer frame.
USB_TRANSFER_BINARY_FRAME_VERSION = 1
USB_TRANSFER_BINARY_REQUEST_ID_LENGTH = 36
USB_TRANSFER_BINARY_HEADER_SIZE = 42

AOA_AUTH_CHALLENGE_REQUEST_ID = USB_AUTH_CHALLENGE_REQUEST_ID.ljust(
    AOA_REQUEST_ID_LENGTH,
    "0",
)


class UsbAoaTransportAdapter:
    """Desktop-side AOA transport adapter.

    Runs a background thread that probes for AOA devices, authenticates, and
    routes mobile transport envelopes through ``MobileTransportRouter``.
    """

    def __init__(
        self,
        *,
        router: MobileTransportRouter,
        driver: AoaHostDriver | None = None,
        probe_interval_seconds: float = 1.0,
        response_poll_timeout_seconds: float = 0.5,
        auth_challenge_timeout_seconds: float = 2.0,
        resolve_transfer_trust_key: Callable[..., str | None] | None = None,
    ) -> None:
        if probe_interval_seconds <= 0:
            raise ValueError("AOA probe_interval_seconds must be greater than zero.")
        if response_poll_timeout_seconds <= 0:
            raise ValueError(
                "AOA response_poll_timeout_seconds must be greater than zero."
            )
        if auth_challenge_timeout_seconds <= 0:
            raise ValueError(
                "AOA auth_challenge_timeout_seconds must be greater than zero."
            )

        self._router = router
        self._driver = driver or PyUsbAoaHostDriver()
        self._probe_interval_seconds = probe_interval_seconds
        self._response_poll_timeout_seconds = response_poll_timeout_seconds
        self._auth_challenge_timeout_seconds = auth_challenge_timeout_seconds
        self._resolve_transfer_trust_key = resolve_transfer_trust_key

        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._worker_thread: threading.Thread | None = None
        self._asset_upload_stream = TransferAssetUploadStream()
        self._state = UsbTransportState.STOPPED
        self._bootstrap_config: UsbBootstrapConfig | None = None
        self._last_probe_error: str | None = None
        self._active_read_stream: AoaReadStream | None = None
        self._active_write_stream: AoaWriteStream | None = None

    @property
    def state(self) -> UsbTransportState:
        with self._lock:
            return self._state

    @property
    def bootstrap_config(self) -> UsbBootstrapConfig | None:
        with self._lock:
            return self._bootstrap_config

    @property
    def last_probe_error(self) -> str | None:
        with self._lock:
            return self._last_probe_error

    def configure_bootstrap(self, config: UsbBootstrapConfig) -> None:
        with self._lock:
            self._bootstrap_config = config
            self._state = UsbTransportState.CONFIGURED
            self._last_probe_error = None
            self._close_active_stream_locked()
        self._safe_log(
            "info",
            message=(
                "UsbAoaTransportAdapter/configure_bootstrap: "
                f"session_id={config.session_id} suggested_port={config.suggested_port}"
            ),
        )

    def start(self) -> None:
        config = self._require_bootstrap_config()
        worker_thread: threading.Thread | None = None
        with self._lock:
            self._state = UsbTransportState.READY
            self._last_probe_error = None
            self._stop_event.clear()
            if self._worker_thread is None or not self._worker_thread.is_alive():
                worker_thread = threading.Thread(
                    target=self._run_transport_loop,
                    name="mobile-aoa-transport",
                    daemon=True,
                )
                self._worker_thread = worker_thread
        if worker_thread is not None:
            worker_thread.start()
        self._safe_log(
            "debug",
            message=(
                "UsbAoaTransportAdapter/start: started AOA probe loop "
                f"for session_id={config.session_id}"
            ),
        )

    def stop(self) -> None:
        worker_thread: threading.Thread | None
        with self._lock:
            self._stop_event.set()
            worker_thread = self._worker_thread
            self._worker_thread = None
            self._close_active_stream_locked()
            self._state = UsbTransportState.STOPPED
            self._last_probe_error = None
        self._driver.stop()
        if worker_thread is not None and worker_thread.is_alive():
            worker_thread.join(timeout=2.0)

    def build_auth_digest(self, rand: str) -> str:
        config = self._require_bootstrap_config()
        material = f"{config.one_time_passcode}{rand}".encode("utf-8")
        return hashlib.sha256(material).hexdigest()

    def verify_auth_digest(self, *, rand: str, provided_digest: str) -> bool:
        expected_digest = self.build_auth_digest(rand)
        return hmac.compare_digest(expected_digest, provided_digest)

    def _run_transport_loop(self) -> None:
        while not self._stop_event.is_set():
            config = self._require_bootstrap_config()

            try:
                probe_result = self._probe(config)
            except Exception as exc:
                self._set_probe_error(str(exc))
                self._safe_log(
                    "warning",
                    message=(
                        "UsbAoaTransportAdapter/_run_transport_loop: unexpected AOA probe failure; "
                        f"retrying. error={exc}"
                    ),
                )
                self._set_ready_state()
                self._wait_for_retry_interval()
                continue

            if probe_result is None:
                self._set_ready_state()
                self._wait_for_retry_interval()
                continue

            device, read_stream, write_stream = probe_result

            try:
                self._auth_challenge(
                    read_stream=read_stream,
                    write_stream=write_stream,
                    config=config,
                )
                with self._lock:
                    if self._state != UsbTransportState.STOPPED:
                        self._state = UsbTransportState.CONNECTED
                        self._last_probe_error = None
                self._safe_log(
                    "info",
                    message=(
                        "UsbAoaTransportAdapter/_run_transport_loop: AOA connected and authenticated "
                        f"device={device.device_id}"
                    ),
                )
                self._session_loop(
                    device=device,
                    read_stream=read_stream,
                    write_stream=write_stream,
                )
            except (
                OSError,
                RuntimeError,
                TimeoutError,
                AoaFrameError,
            ) as exc:
                self._set_probe_error(str(exc))
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_run_transport_loop: AOA session failed "
                        f"device={device.device_id}: {exc}"
                    ),
                )
            finally:
                self._close_active_stream_locked()
                self._set_ready_state()

            self._wait_for_retry_interval()

    def _probe(
        self,
        config: UsbBootstrapConfig,
    ) -> tuple[AoaDetectedDevice, AoaReadStream, AoaWriteStream] | None:
        # config is currently unused but kept for future capability matching.
        _ = config
        self._driver.start()

        devices = self._driver.detect_devices()
        if not devices:
            return None

        for device in devices:
            target_device = device
            if not device.is_accessory_mode:
                if not self._driver.ensure_accessory_mode(device):
                    continue
                post_devices = self._driver.detect_devices()
                accessory = next(
                    (candidate for candidate in post_devices if candidate.is_accessory_mode),
                    None,
                )
                if accessory is None:
                    continue
                target_device = accessory

            try:
                read_stream, write_stream = self._driver.open_stream(target_device)
            except RuntimeError as exc:
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_probe: could not open AOA stream for "
                        f"device={target_device.device_id}: {exc}"
                    ),
                )
                continue

            with self._lock:
                self._active_read_stream = read_stream
                self._active_write_stream = write_stream
            return target_device, read_stream, write_stream

        return None

    def _auth_challenge(
        self,
        *,
        read_stream: AoaReadStream,
        write_stream: AoaWriteStream,
        config: UsbBootstrapConfig,
    ) -> None:
        challenge_rand = secrets.token_hex(16)
        challenge_envelope = {
            "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
            "operation": USB_AUTH_CHALLENGE_OPERATION,
            "request_id": AOA_AUTH_CHALLENGE_REQUEST_ID,
            "body_schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
            "body": {
                "schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
                "sid": config.session_id,
                "rand": challenge_rand,
            },
        }
        self._send_frame(
            write_stream=write_stream,
            request_id=AOA_AUTH_CHALLENGE_REQUEST_ID,
            payload=json.dumps(
                challenge_envelope,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8"),
        )

        decoder = AoaFrameDecoder()
        deadline = time.monotonic() + self._auth_challenge_timeout_seconds
        while not self._stop_event.is_set() and time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            read_timeout = min(self._response_poll_timeout_seconds, max(remaining, 0.01))
            try:
                chunk = read_stream.read(8192, timeout=read_timeout)
            except TimeoutError:
                continue
            if not chunk:
                continue

            for request_id, flags, payload in decoder.feed(chunk):
                if request_id != AOA_AUTH_CHALLENGE_REQUEST_ID:
                    continue
                if flags != AOA_FRAME_FLAG_TEXT:
                    continue
                try:
                    challenge_response = json.loads(payload.decode("utf-8"))
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                if not isinstance(challenge_response, dict):
                    continue

                status_code = challenge_response.get("status_code")
                if not isinstance(status_code, int):
                    raise RuntimeError(
                        "Desktop AOA auth challenge returned an invalid status code."
                    )
                response_body = challenge_response.get("body")
                if not isinstance(response_body, dict):
                    raise RuntimeError(
                        "Desktop AOA auth challenge returned an invalid response body."
                    )
                if not (200 <= status_code < 300):
                    rejection_message = response_body.get("message")
                    if isinstance(rejection_message, str) and rejection_message.strip():
                        raise RuntimeError(
                            "Desktop AOA auth challenge was rejected by mobile runtime: "
                            f"{rejection_message.strip()}"
                        )
                    raise RuntimeError(
                        "Desktop AOA auth challenge was rejected by mobile runtime."
                    )

                challenge_proof = response_body.get("proof")
                if not isinstance(challenge_proof, str) or not challenge_proof.strip():
                    raise RuntimeError(
                        "Desktop AOA auth challenge response did not include a proof digest."
                    )
                if not self.verify_auth_digest(
                    rand=challenge_rand,
                    provided_digest=challenge_proof.strip(),
                ):
                    raise RuntimeError(
                        "Desktop AOA auth challenge proof digest verification failed."
                    )
                return

        if self._stop_event.is_set():
            raise RuntimeError("Desktop stopped while waiting for AOA auth challenge response.")
        raise RuntimeError("Desktop AOA auth challenge timed out.")

    def _session_loop(
        self,
        *,
        device: AoaDetectedDevice,
        read_stream: AoaReadStream,
        write_stream: AoaWriteStream,
    ) -> None:
        remote_address = f"aoa://{device.device_id}"
        decoder = AoaFrameDecoder()
        while not self._stop_event.is_set():
            try:
                chunk = read_stream.read(8192, timeout=self._response_poll_timeout_seconds)
            except TimeoutError:
                continue
            if not chunk:
                raise RuntimeError("AOA stream closed by mobile runtime.")

            frames = decoder.feed(chunk)
            for request_id, flags, payload in frames:
                if flags == AOA_FRAME_FLAG_BINARY:
                    self._append_pending_asset_chunk(payload)
                    continue

                try:
                    raw_message = payload.decode("utf-8")
                except UnicodeDecodeError:
                    self._safe_log(
                        "debug",
                        message=(
                            "UsbAoaTransportAdapter/_session_loop: "
                            "ignored non-UTF8 AOA frame from mobile runtime."
                        ),
                    )
                    continue

                response_request_id, response = self._dispatch_envelope_request(
                    raw_message,
                    remote_address=remote_address,
                )
                if response is None:
                    continue
                if response_request_id is None:
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_session_loop: "
                            "skipping AOA response because request_id is missing."
                        ),
                    )
                    continue

                self._send_frame(
                    write_stream=write_stream,
                    request_id=response_request_id,
                    payload=self._encode_response_envelope(
                        request_id=response_request_id,
                        response=response,
                    ).encode("utf-8"),
                )

    def _send_frame(
        self,
        write_stream: AoaWriteStream,
        request_id: str,
        payload: bytes,
        flags: int = AOA_FRAME_FLAG_TEXT,
    ) -> None:
        frame = encode_aoa_frame(request_id, payload, flags=flags)
        write_stream.write(frame)

    def _dispatch_envelope_request(
        self,
        raw_message: str,
        *,
        remote_address: str | None,
    ) -> tuple[str | None, MobileTransportResponse | None]:
        parsed_envelope = self._parse_envelope(raw_message)
        if isinstance(parsed_envelope, MobileTransportResponse):
            return self._extract_request_id(raw_message), parsed_envelope

        operation = parsed_envelope["operation"]
        request_id = parsed_envelope.get("request_id")
        if not isinstance(request_id, str) or not request_id.strip():
            return None, self._transport_error_response(
                message="Desktop rejected a USB transport message with a missing request id.",
            )
        request_id = request_id.strip()

        payload_or_error: dict[str, object] | TransferAssetUploadPayload | MobileTransportResponse | None = None
        if operation == TRANSFER_ASSET_OPERATION:
            payload_or_error = self._dispatch_transfer_asset_stream_payload(
                request_id=request_id,
                raw_body=parsed_envelope.get("body"),
            )
            if payload_or_error is None:
                return request_id, None
            if isinstance(payload_or_error, MobileTransportResponse):
                return request_id, payload_or_error
        else:
            raw_body = parsed_envelope.get("body")
            if raw_body is None:
                payload_or_error = {}
            elif isinstance(raw_body, dict):
                payload_or_error = raw_body
            else:
                return request_id, self._transport_error_response(
                    message=(
                        "Desktop requires JSON object payloads for "
                        f"USB transport operation '{operation}'."
                    ),
                )

        context = MobileTransportContext(
            transport=MobileTransportKind.AOA_USB,
            operation=operation,
            request_id=request_id,
            remote_address=remote_address,
        )

        try:
            response = self._router.dispatch(
                operation=operation,
                payload=payload_or_error,
                context=context,
            )
        except MobileTransportRouteNotFoundError:
            response = self._transport_error_response(
                message=f"Desktop does not support USB transport operation '{operation}'.",
            )
        finally:
            if isinstance(payload_or_error, TransferAssetUploadPayload):
                body_stream = getattr(payload_or_error, "body_stream", None)
                if body_stream is not None:
                    body_stream.close()
        return request_id, response

    def _dispatch_transfer_asset_stream_payload(
        self,
        *,
        request_id: str,
        raw_body: object,
    ) -> TransferAssetUploadPayload | MobileTransportResponse | None:
        if not isinstance(raw_body, dict):
            return self._transport_error_response(
                message="Desktop requires JSON object payloads for transfer asset requests.",
            )

        stream_state = raw_body.get(TRANSFER_ASSET_STREAM_STATE_FIELD)
        if stream_state == TRANSFER_ASSET_STREAM_STATE_START:
            metadata_payload = dict(raw_body)
            metadata_payload.pop(TRANSFER_ASSET_STREAM_STATE_FIELD, None)
            metadata_payload.pop("chunk_size", None)
            encrypted_chunk_trust_key: str | None = None
            if is_mobile_encrypted_payload(metadata_payload):
                (
                    metadata_payload,
                    encrypted_chunk_trust_key,
                    decrypt_error_message,
                ) = self._decrypt_transfer_asset_stream_metadata(
                    metadata_payload=metadata_payload,
                )
                if decrypt_error_message is not None:
                    return self._transport_error_response(
                        message=decrypt_error_message,
                    )
            self._start_pending_asset_upload(
                request_id=request_id,
                metadata_payload=metadata_payload,
                encryption_trust_key_b64=encrypted_chunk_trust_key,
            )
            return None
        if stream_state == TRANSFER_ASSET_STREAM_STATE_COMPLETE:
            return self._complete_pending_asset_upload(request_id=request_id)

        return self._transport_error_response(
            message=(
                "Desktop rejected transfer asset stream message with an unsupported "
                f"'{TRANSFER_ASSET_STREAM_STATE_FIELD}' value."
            )
        )

    def _start_pending_asset_upload(
        self,
        *,
        request_id: str,
        metadata_payload: dict[str, object],
        encryption_trust_key_b64: str | None = None,
    ) -> None:
        with self._lock:
            self._asset_upload_stream.start(
                request_id=request_id,
                metadata_payload=metadata_payload,
                encryption_trust_key_b64=encryption_trust_key_b64,
            )

    def _append_pending_asset_chunk(self, chunk: bytes) -> None:
        framed_request_id, frame_payload = self._decode_transfer_asset_binary_frame(chunk)
        with self._lock:
            encrypted_chunk_trust_key = self._asset_upload_stream.encryption_trust_key(
                request_id=framed_request_id,
            )
        if encrypted_chunk_trust_key is not None:
            try:
                frame_payload = decrypt_mobile_binary_chunk(
                    encrypted_chunk=frame_payload,
                    trust_key_b64=encrypted_chunk_trust_key,
                )
            except MobilePayloadEncryptionError as exc:
                raise RuntimeError(str(exc)) from exc
        append_error: str | None = None
        with self._lock:
            append_error = self._asset_upload_stream.append_chunk(
                chunk=frame_payload,
                request_id=framed_request_id,
            )
            active_request_id = self._asset_upload_stream.active_request_id
        if append_error is None:
            return
        if not frame_payload:
            return
        if len(frame_payload) > TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES:
            raise RuntimeError(append_error)
        if active_request_id is None:
            self._safe_log(
                "warning",
                message=(
                    "UsbAoaTransportAdapter/_append_pending_asset_chunk: "
                    "ignoring binary frame without a matching transfer asset start envelope."
                ),
            )
            return
        raise RuntimeError(append_error)

    def _decode_transfer_asset_binary_frame(self, frame: bytes) -> tuple[str, bytes]:
        if len(frame) < USB_TRANSFER_BINARY_HEADER_SIZE:
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because binary frame header is incomplete."
            )

        frame_version = frame[0]
        if frame_version != USB_TRANSFER_BINARY_FRAME_VERSION:
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because binary frame version is unsupported."
            )

        request_id_bytes = frame[1 : 1 + USB_TRANSFER_BINARY_REQUEST_ID_LENGTH]
        try:
            request_id = request_id_bytes.decode("ascii").strip()
        except UnicodeDecodeError as exc:
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because the request id is invalid."
            ) from exc
        if not request_id:
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because the request id is missing."
            )
        if len(request_id) != USB_TRANSFER_BINARY_REQUEST_ID_LENGTH:
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because the request id length is invalid."
            )

        payload_length_start = 1 + USB_TRANSFER_BINARY_REQUEST_ID_LENGTH
        payload_length_end = payload_length_start + 4
        declared_payload_length = int.from_bytes(
            frame[payload_length_start:payload_length_end],
            byteorder="big",
            signed=False,
        )
        frame_payload = frame[USB_TRANSFER_BINARY_HEADER_SIZE:]
        if declared_payload_length != len(frame_payload):
            raise RuntimeError(
                "Desktop rejected transfer asset stream chunk because binary frame length does not match the header."
            )
        return request_id, frame_payload

    def _decrypt_transfer_asset_stream_metadata(
        self,
        *,
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

    def _complete_pending_asset_upload(
        self,
        *,
        request_id: str,
    ) -> TransferAssetUploadPayload | MobileTransportResponse:
        with self._lock:
            payload_or_error = self._asset_upload_stream.complete(request_id=request_id)
        if isinstance(payload_or_error, str):
            return self._transport_error_response(
                message=payload_or_error,
            )
        return payload_or_error

    def _encode_response_envelope(
        self,
        *,
        request_id: str,
        response: MobileTransportResponse,
    ) -> str:
        return json.dumps(
            {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "request_id": request_id,
                "status_code": response.status_code,
                "body": response.payload,
            },
            separators=(",", ":"),
            sort_keys=True,
        )

    def _extract_request_id(self, raw_message: str) -> str | None:
        try:
            parsed_value = json.loads(raw_message)
        except json.JSONDecodeError:
            return None
        if not isinstance(parsed_value, dict):
            return None
        request_id = parsed_value.get("request_id")
        if not isinstance(request_id, str) or not request_id.strip():
            return None
        return request_id.strip()

    def _parse_envelope(self, raw_message: str) -> dict[str, object] | MobileTransportResponse:
        try:
            parsed_value = json.loads(raw_message)
        except json.JSONDecodeError:
            return self._transport_error_response(
                message="Desktop could not parse the USB transport envelope JSON payload.",
            )

        if not isinstance(parsed_value, dict):
            return self._transport_error_response(
                message="Desktop requires JSON object envelopes for USB transport messages.",
            )

        schema = parsed_value.get("schema")
        if schema != MOBILE_TRANSPORT_ENVELOPE_SCHEMA:
            return self._transport_error_response(
                message="Desktop rejected an unsupported USB transport schema.",
            )

        operation = parsed_value.get("operation")
        if not isinstance(operation, str) or not operation.strip():
            return self._transport_error_response(
                message="Desktop rejected a USB transport message with a missing operation.",
            )

        return parsed_value

    def _transport_error_response(self, *, message: str) -> MobileTransportResponse:
        return MobileTransportResponse(
            status_code=400,
            payload={
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "status": USB_TRANSPORT_REJECTED_STATUS,
                "message": message,
            },
        )

    def _require_bootstrap_config(self) -> UsbBootstrapConfig:
        with self._lock:
            if self._bootstrap_config is None:
                raise RuntimeError("AOA bootstrap config is not available.")
            return self._bootstrap_config

    def _set_probe_error(self, message: str | None) -> None:
        with self._lock:
            self._last_probe_error = message

    def _set_ready_state(self) -> None:
        with self._lock:
            if self._state != UsbTransportState.STOPPED:
                self._state = UsbTransportState.READY

    def _wait_for_retry_interval(self) -> None:
        self._stop_event.wait(timeout=self._probe_interval_seconds)

    def _close_active_stream_locked(self) -> None:
        with self._lock:
            read_stream = self._active_read_stream
            write_stream = self._active_write_stream
            self._active_read_stream = None
            self._active_write_stream = None
            self._asset_upload_stream.clear()
        for stream in (read_stream, write_stream):
            if stream is not None:
                try:
                    stream.close()
                except (OSError, RuntimeError):
                    pass

    def _safe_log(
        self,
        severity: str,
        *,
        message: str,
        error_type: str = "",
        where: str = "",
        attributes: dict[str, object] | None = None,
    ) -> None:
        try:
            log(
                severity,
                error_type=error_type,
                where=where or "UsbAoaTransportAdapter",
                message=message,
                attributes=attributes,
            )
        except Exception:
            return
