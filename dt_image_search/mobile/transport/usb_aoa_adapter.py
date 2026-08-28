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

AOA_AUTH_CHALLENGE_REQUEST_ID = USB_AUTH_CHALLENGE_REQUEST_ID.ljust(
    AOA_REQUEST_ID_LENGTH,
    "0",
)

# Read the AOA bulk IN endpoint in large pieces so each ~1 MB chunk frame is
# reassembled in one or two libusb bulk_read calls instead of ~128 eight-KB
# round trips. This was the desktop-side throughput bottleneck (~15 MB/s vs the
# USB link's capacity) and let the mobile's unbounded outgoing queue grow until
# its completion frames exceeded the 10 s streaming-response timeout.
AOA_SESSION_READ_SIZE_BYTES = 1_048_576


def _is_access_denied_error(exc: BaseException) -> bool:
    """Detect USB permission denials (e.g. macOS TCC 'USB' privacy denial).

    libusb reports these as LIBUSB_ERROR_ACCESS, which pyusb surfaces as
    ``[Errno 13] Access denied (insufficient permissions)``.
    """
    error_message = str(exc).lower()
    return (
        "access denied" in error_message
        or "insufficient permissions" in error_message
        or getattr(exc, "errno", None) == 13
    )


def _is_mobile_not_ready_error(exc: BaseException) -> bool:
    """Detect AOA auth failures caused by the mobile not being ready yet.

    Before the mobile scans the QR and prepares its AOA client, the desktop's
    auth challenge goes unanswered and times out. This is the normal pre-pairing
    state and should not be logged as a session failure.
    """
    error_message = str(exc).lower()
    return "auth challenge timed out" in error_message


class AoaSessionStallError(RuntimeError):
    """Raised when an in-flight AOA asset upload goes silent for too long.

    The mobile can be frozen by the OS (screen off / battery optimization)
    mid-upload. Its own watchdog eventually re-opens the accessory stream, but
    the host's read loop would otherwise time out forever without ever returning
    to the probe loop to re-authenticate the fresh stream.
    """


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
        open_retry_attempts: int = 3,
        open_retry_delay_seconds: float = 0.25,
        resolve_transfer_trust_key: Callable[..., str | None] | None = None,
        max_session_failure_backoff_seconds: float = 5.0,
        session_stall_timeout_seconds: float = 60.0,
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
        if open_retry_attempts <= 0:
            raise ValueError("AOA open_retry_attempts must be greater than zero.")
        if open_retry_delay_seconds < 0:
            raise ValueError("AOA open_retry_delay_seconds must not be negative.")
        if max_session_failure_backoff_seconds < 0:
            raise ValueError(
                "AOA max_session_failure_backoff_seconds must not be negative."
            )
        if session_stall_timeout_seconds <= 0:
            raise ValueError(
                "AOA session_stall_timeout_seconds must be greater than zero."
            )

        self._router = router
        self._driver = driver or PyUsbAoaHostDriver()
        self._probe_interval_seconds = probe_interval_seconds
        self._response_poll_timeout_seconds = response_poll_timeout_seconds
        self._auth_challenge_timeout_seconds = auth_challenge_timeout_seconds
        self._open_retry_attempts = open_retry_attempts
        self._open_retry_delay_seconds = open_retry_delay_seconds
        self._resolve_transfer_trust_key = resolve_transfer_trust_key
        self._max_session_failure_backoff_seconds = max_session_failure_backoff_seconds
        self._session_stall_timeout_seconds = session_stall_timeout_seconds

        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._worker_thread: threading.Thread | None = None
        self._asset_upload_stream = TransferAssetUploadStream()
        self._state = UsbTransportState.STOPPED
        self._bootstrap_config: UsbBootstrapConfig | None = None
        self._last_probe_error: str | None = None
        self._active_read_stream: AoaReadStream | None = None
        self._active_write_stream: AoaWriteStream | None = None
        self._consecutive_session_failures = 0

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
                    self._consecutive_session_failures = 0
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
            except AoaSessionStallError as exc:
                # The mobile went silent mid-upload (e.g. the OS froze the app).
                # Tear down and re-probe so the host re-authenticates the fresh
                # stream the mobile re-opens; a stall is a recovery event, not a
                # session failure, so it must not trigger the failure backoff.
                self._safe_log(
                    "warning",
                    message=(
                        "UsbAoaTransportAdapter/_run_transport_loop: AOA session "
                        f"stalled device={device.device_id}: {exc}; re-probing."
                    ),
                )
            except (
                OSError,
                RuntimeError,
                TimeoutError,
                AoaFrameError,
            ) as exc:
                self._set_probe_error(str(exc))
                with self._lock:
                    self._consecutive_session_failures += 1
                if _is_mobile_not_ready_error(exc):
                    # The mobile has not prepared its AOA client yet (e.g. the user
                    # has not scanned the QR). This is the normal pre-pairing state;
                    # keep probing quietly instead of logging a session failure.
                    self._safe_log(
                        "debug",
                        message=(
                            "UsbAoaTransportAdapter/_run_transport_loop: "
                            f"device={device.device_id} not ready for AOA auth yet; "
                            f"retrying. ({exc})"
                        ),
                    )
                else:
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_run_transport_loop: AOA session failed "
                            f"device={device.device_id}: {exc} "
                            f"(consecutive_failures={self._consecutive_session_failures})"
                        ),
                    )
            finally:
                self._close_active_stream_locked()
                try:
                    self._driver.stop()
                except Exception as release_exc:  # noqa: BLE001
                    self._safe_log(
                        "debug",
                        message=(
                            "UsbAoaTransportAdapter/_run_transport_loop: AOA driver "
                            f"release failed for device={device.device_id}: {release_exc}"
                        ),
                    )
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
            self._safe_log(
                "debug",
                message=(
                    "UsbAoaTransportAdapter/_probe: no AOA-capable USB devices detected."
                ),
            )
            return None

        for device in devices:
            target_device = device
            if not device.is_accessory_mode:
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_probe: negotiating accessory mode for "
                        f"device={device.device_id} vendor_id=0x{device.vendor_id:04x} "
                        f"product_id=0x{device.product_id:04x}"
                    ),
                )
                if not self._driver.ensure_accessory_mode(device):
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_probe: accessory mode negotiation "
                            f"failed for device={device.device_id}"
                        ),
                    )
                    continue
                post_devices = self._driver.detect_devices()
                accessory = next(
                    (candidate for candidate in post_devices if candidate.is_accessory_mode),
                    None,
                )
                if accessory is None:
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_probe: device did not re-enumerate in "
                            f"accessory mode after negotiation device={device.device_id}"
                        ),
                    )
                    continue
                target_device = accessory
                self._safe_log(
                    "info",
                    message=(
                        "UsbAoaTransportAdapter/_probe: device entered accessory mode "
                        f"device={accessory.device_id} product_id=0x{accessory.product_id:04x}"
                    ),
                )

            try:
                read_stream, write_stream = self._open_accessory_stream(target_device)
            except RuntimeError as exc:
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_probe: could not open AOA stream for "
                        f"device={target_device.device_id}: {exc}"
                    ),
                )
                continue

            self._safe_log(
                "info",
                message=(
                    "UsbAoaTransportAdapter/_probe: opened AOA bulk streams for "
                    f"device={target_device.device_id}"
                ),
            )
            with self._lock:
                self._active_read_stream = read_stream
                self._active_write_stream = write_stream
            return target_device, read_stream, write_stream

        return None

    def _open_accessory_stream(
        self,
        device: AoaDetectedDevice,
    ) -> tuple[AoaReadStream, AoaWriteStream]:
        """Open the accessory bulk streams, tolerating the re-enumeration window.

        Right after AOA negotiation the accessory device can drop off the bus for a
        few hundred milliseconds. A single failed open must not abort the probe pass:
        re-detect so the driver re-finds the device at its current bus/address and
        retry until the device is stable. Access-denied errors are not transient and
        are surfaced immediately with remediation guidance instead of being retried.
        """
        last_error: RuntimeError | None = None
        target_device = device
        for _ in range(self._open_retry_attempts):
            if self._stop_event.is_set():
                break
            try:
                return self._driver.open_stream(target_device)
            except RuntimeError as exc:
                last_error = exc
                if _is_access_denied_error(exc):
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_open_accessory_stream: macOS denied "
                            f"USB access to the AOA accessory device "
                            f"device={target_device.device_id}: {exc}. "
                            "Grant the app (or the terminal/IDE that launched it) USB "
                            "permission in System Settings > Privacy & Security > USB, "
                            "then reconnect the phone."
                        ),
                    )
                    break
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_open_accessory_stream: retrying AOA "
                        f"stream open for device={target_device.device_id}: {exc}"
                    ),
                )
                re_detected = self._driver.detect_devices()
                fresh_accessory = next(
                    (
                        candidate
                        for candidate in re_detected
                        if candidate.is_accessory_mode
                    ),
                    None,
                )
                if fresh_accessory is not None:
                    target_device = fresh_accessory
                if self._stop_event.wait(timeout=self._open_retry_delay_seconds):
                    break
        if last_error is not None:
            raise last_error
        raise RuntimeError("AOA host stopped while opening the accessory stream.")

    def _auth_challenge(
        self,
        *,
        read_stream: AoaReadStream,
        write_stream: AoaWriteStream,
        config: UsbBootstrapConfig,
    ) -> None:
        # A freshly opened bulk IN endpoint can still hold stale bytes from a
        # desynchronized stream generation (e.g. the OS froze the mobile or the
        # app was reloaded). Reading them during the handshake raises
        # "Unsupported AOA frame version" and makes the desktop re-probe forever
        # without ever re-establishing. Drain them before the handshake.
        self._drain_stale_stream_bytes(read_stream)

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
        self._safe_log(
            "debug",
            message=(
                "UsbAoaTransportAdapter/_auth_challenge: sent AOA auth challenge "
                f"session_id={config.session_id} rand_len={len(challenge_rand)}"
            ),
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

            try:
                frames = decoder.feed(chunk)
            except AoaFrameError:
                # The stream is still desynchronized (stale bytes). Discard the
                # chunk and keep waiting for a valid frame instead of failing the
                # session; the mobile re-establishes a clean stream on resync.
                decoder.reset()
                continue

            for request_id, flags, payload in frames:
                if request_id != AOA_AUTH_CHALLENGE_REQUEST_ID:
                    self._safe_log(
                        "debug",
                        message=(
                            "UsbAoaTransportAdapter/_auth_challenge: ignored frame with "
                            f"unrelated request_id={request_id!r} flags={flags}"
                        ),
                    )
                    continue
                if flags != AOA_FRAME_FLAG_TEXT:
                    self._safe_log(
                        "debug",
                        message=(
                            "UsbAoaTransportAdapter/_auth_challenge: ignored non-text "
                            f"auth frame flags={flags}"
                        ),
                    )
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
                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_auth_challenge: mobile authenticated "
                        f"session_id={config.session_id} status_code={status_code}"
                    ),
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
        last_frame_received_at = time.monotonic()
        while not self._stop_event.is_set():
            try:
                chunk = read_stream.read(
                    AOA_SESSION_READ_SIZE_BYTES,
                    timeout=self._response_poll_timeout_seconds,
                )
            except TimeoutError:
                self._raise_if_session_stalled(last_frame_received_at)
                continue
            if not chunk:
                raise RuntimeError("AOA stream closed by mobile runtime.")
            last_frame_received_at = time.monotonic()

            frames = decoder.feed(chunk)
            for frame_request_id, flags, payload in frames:
                if flags == AOA_FRAME_FLAG_BINARY:
                    self._append_aoa_binary_chunk(
                        request_id=frame_request_id,
                        payload=payload,
                    )
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

                envelope_request_id, response = self._dispatch_envelope_request(
                    raw_message,
                    remote_address=remote_address,
                )
                if response is None:
                    continue
                if envelope_request_id is None:
                    self._safe_log(
                        "warning",
                        message=(
                            "UsbAoaTransportAdapter/_session_loop: "
                            "skipping AOA response because request_id is missing."
                        ),
                    )
                    continue

                self._safe_log(
                    "debug",
                    message=(
                        "UsbAoaTransportAdapter/_session_loop: dispatched AOA request "
                        f"request_id={envelope_request_id} "
                        f"status_code={response.status_code}"
                    ),
                )
                self._send_frame(
                    write_stream=write_stream,
                    # The mobile frames requests with the request_id padded to 36
                    # bytes while the envelope keeps the unpadded id used for
                    # correlation. Echo the 36-byte frame id so encode_aoa_frame
                    # accepts the response frame; the envelope keeps the unpadded id.
                    request_id=frame_request_id,
                    payload=self._encode_response_envelope(
                        request_id=envelope_request_id,
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

    def _drain_stale_stream_bytes(self, read_stream: AoaReadStream) -> None:
        """Discard stale bytes from a freshly-opened bulk IN endpoint.

        After the mobile is frozen by the OS (or the app is reloaded), the
        gadget's IN endpoint can hold leftover bytes from the desynchronized
        stream. Reading them during the auth handshake raises "Unsupported AOA
        frame version" and makes the desktop re-probe endlessly without ever
        re-establishing. Draining until the endpoint is quiet realigns the
        stream before the handshake.
        """
        for _ in range(8):
            if self._stop_event.is_set():
                return
            try:
                chunk = read_stream.read(AOA_SESSION_READ_SIZE_BYTES, timeout=0.05)
            except (TimeoutError, OSError, RuntimeError):
                return
            if not chunk:
                return
            self._safe_log(
                "debug",
                message=(
                    "UsbAoaTransportAdapter/_drain_stale_stream_bytes: discarded "
                    f"{len(chunk)} stale bytes from the AOA IN endpoint."
                ),
            )

    def _raise_if_session_stalled(self, last_frame_received_at: float) -> None:
        """Abort a session whose in-flight asset upload went silent.

        The mobile can be frozen by the OS (screen off / battery optimization)
        mid-upload. The host's read loop would otherwise time out forever and
        never return to the probe loop, so when a fresh stream the mobile
        re-opens after thawing can never be re-authenticated. Only a session
        with an unfinished upload is considered stalled: an idle-but-healthy
        session (phone connected, nothing being transferred) legitimately has no
        inbound frames and must be left alone.
        """
        with self._lock:
            has_pending_upload = self._asset_upload_stream.has_pending
        if not has_pending_upload:
            return
        idle_seconds = time.monotonic() - last_frame_received_at
        if idle_seconds >= self._session_stall_timeout_seconds:
            raise AoaSessionStallError(
                "AOA session stalled: no frames received for "
                f"{idle_seconds:.1f}s while an asset upload was in progress."
            )

    def _dispatch_envelope_request(
        self,
        raw_message: str,
        *,
        remote_address: str | None,
    ) -> tuple[str | None, MobileTransportResponse | None]:
        parsed_envelope = self._parse_envelope(raw_message)
        if isinstance(parsed_envelope, MobileTransportResponse):
            self._safe_log(
                "warning",
                message=(
                    f"UsbAoaTransportAdapter/_dispatch_envelope_request sth failed: {raw_message}"
                ),
            )
            return self._extract_request_id(raw_message), parsed_envelope

        self._safe_log(
            "debug",
            message=(
                f"UsbAoaTransportAdapter/_dispatch_envelope_request parsed: {parsed_envelope}"
            ),
        )
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

    def _append_aoa_binary_chunk(
        self,
        *,
        request_id: str,
        payload: bytes,
    ) -> None:
        """Append a raw binary asset chunk tied to the active streaming request.

        The AOA frame already carries the request_id and flags, so the chunk bytes
        are used directly without an additional inner binary frame header.
        """
        with self._lock:
            encrypted_chunk_trust_key = self._asset_upload_stream.encryption_trust_key(
                request_id=request_id,
            )
        frame_payload = payload
        if encrypted_chunk_trust_key is not None:
            try:
                frame_payload = decrypt_mobile_binary_chunk(
                    encrypted_chunk=payload,
                    trust_key_b64=encrypted_chunk_trust_key,
                )
            except MobilePayloadEncryptionError as exc:
                raise RuntimeError(str(exc)) from exc

        append_error: str | None = None
        with self._lock:
            append_error = self._asset_upload_stream.append_chunk(
                chunk=frame_payload,
                request_id=request_id,
            )
            active_request_id = self._asset_upload_stream.active_request_id
        if append_error is None:
            self._safe_log(
                "debug",
                message=(
                    f"UsbAoaTransportAdapter/_append_aoa_binary_chunk: {len(frame_payload)} bytes, request_id={request_id}"
                ),
            )
            return
        self._safe_log(
            "warning",
            message=(
                f"UsbAoaTransportAdapter/_append_aoa_binary_chunk: failed to append {len(frame_payload)} bytes to request_id={request_id}: {append_error}"
            ),
        )
        if not frame_payload:
            return
        if len(frame_payload) > TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES:
            raise RuntimeError(append_error)
        if active_request_id is None:
            self._safe_log(
                "warning",
                message=(
                    "UsbAoaTransportAdapter/_append_aoa_binary_chunk: "
                    "ignoring binary frame without a matching transfer asset start envelope."
                ),
            )
            return
        raise RuntimeError(append_error)

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
        # Back off after repeated AOA session failures (e.g. a mobile process that
        # was frozen by the OS and is now resyncing its accessory streams). A slow
        # reconnect loop gives the mobile time to re-establish clean streams instead
        # of the host hammering the USB bus with probe/auth attempts.
        with self._lock:
            failure_count = self._consecutive_session_failures
        if failure_count <= 1:
            wait_seconds = self._probe_interval_seconds
        else:
            wait_seconds = min(
                self._probe_interval_seconds * (2 ** min(failure_count - 1, 4)),
                self._max_session_failure_backoff_seconds,
            )
        self._stop_event.wait(timeout=wait_seconds)

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
