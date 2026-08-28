#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the desktop AOA USB transport adapter."""

from __future__ import annotations

import hashlib
import json
import time
import unittest

from dt_image_search.mobile.transport import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    PAIRING_CLAIM_OPERATION,
    TRANSFER_ASSET_OPERATION,
    AOA_FRAME_FLAG_TEXT,
    AoaDetectedDevice,
    MobileTransportRequest,
    MobileTransportResponse,
    MobileTransportRouter,
    SimulatedAoaHostDriver,
    UsbAoaTransportAdapter,
    decode_aoa_frame,
    encode_aoa_frame,
)
from dt_image_search.mobile.transport.usb_ws_adapter import UsbBootstrapConfig
from dt_image_search.mobile.transport.usb_aoa_adapter import AOA_AUTH_CHALLENGE_REQUEST_ID


CLAIM_REQUEST_ID = "claim-001".ljust(36, "0")


def _build_auth_response(rand: str, opt: str, request_id: str) -> bytes:
    proof = hashlib.sha256(f"{opt}{rand}".encode("utf-8")).hexdigest()
    envelope = {
        "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
        "request_id": request_id,
        "status_code": 200,
        "body": {
            "schema": "dtis.mobile-pairing.v1",
            "status": "accepted",
            "proof": proof,
        },
    }
    return json.dumps(envelope, separators=(",", ":"), sort_keys=True).encode("utf-8")


class _StubAoaStream:
    def read(self, size: int = -1, timeout: float | None = None) -> bytes:
        return b""

    def write(self, data: bytes) -> int:
        return len(data)

    def close(self) -> None:
        return None


class _FlakyOpenAoaDriver(SimulatedAoaHostDriver):
    """Simulated driver whose open_stream fails a fixed number of times."""

    def __init__(self, *, failures_before_success: int, accessory_device: AoaDetectedDevice) -> None:
        super().__init__([accessory_device])
        self._failures_before_success = failures_before_success
        self._accessory_device = accessory_device
        self.open_attempts = 0

    def open_stream(self, device: AoaDetectedDevice):
        self.open_attempts += 1
        if self.open_attempts <= self._failures_before_success:
            raise RuntimeError(
                "AOA stream setup failed: [Errno 19] No such device (it may have been disconnected)"
            )
        return _StubAoaStream(), _StubAoaStream()


class _AccessDeniedAoaDriver(SimulatedAoaHostDriver):
    """Simulated driver whose open_stream always fails with an access-denied error."""

    def __init__(self, *, accessory_device: AoaDetectedDevice) -> None:
        super().__init__([accessory_device])
        self._accessory_device = accessory_device
        self.open_attempts = 0

    def open_stream(self, device: AoaDetectedDevice):
        self.open_attempts += 1
        raise RuntimeError(
            "AOA stream setup failed at claim_interface: [Errno 13] Access denied (insufficient permissions)"
        )


class _TrackingStopDriver(SimulatedAoaHostDriver):
    """Simulated driver that records every stop()/release call."""

    def __init__(self, *, accessory_device: AoaDetectedDevice) -> None:
        super().__init__([accessory_device])
        self._accessory_device = accessory_device
        self.stop_calls = 0

    def stop(self) -> None:
        self.stop_calls += 1
        super().stop()


class _StaleFirstReadStream:
    """Wraps a read stream and returns stale garbage bytes on the first read.

    Models the gadget's bulk IN endpoint holding leftover bytes from a
    desynchronized stream generation (e.g. after the OS froze the mobile or the
    app was reloaded).
    """

    def __init__(self, wrapped: _StubAoaStream, stale_bytes: bytes) -> None:
        self._wrapped = wrapped
        self._stale_bytes = stale_bytes

    def read(self, size: int = -1, timeout: float | None = None) -> bytes:
        if self._stale_bytes is not None:
            stale = self._stale_bytes
            self._stale_bytes = None
            return stale
        return self._wrapped.read(size, timeout)

    def write(self, data: bytes) -> int:
        return self._wrapped.write(data)

    def close(self) -> None:
        return self._wrapped.close()


class _StaleReadAoaDriver(SimulatedAoaHostDriver):
    """Simulated driver whose freshly-opened IN stream returns stale garbage on
    the first read, on every stream generation (persistent desync)."""

    def __init__(
        self,
        accessory_device: AoaDetectedDevice,
        stale_bytes: bytes,
    ) -> None:
        super().__init__([accessory_device])
        self._stale_bytes = stale_bytes

    def open_stream(self, device: AoaDetectedDevice):
        read_stream, write_stream = super().open_stream(device)
        return _StaleFirstReadStream(read_stream, self._stale_bytes), write_stream


class TestUsbAoaTransportAdapter(unittest.TestCase):
    def test_pairing_claim_round_trip(self) -> None:
        router = MobileTransportRouter()

        def handle_claim(request: MobileTransportRequest) -> MobileTransportResponse:
            payload = request.payload
            self.assertEqual(payload.get("sid"), "sid-001")
            self.assertEqual(payload.get("opt"), "123456")
            return MobileTransportResponse(
                status_code=200,
                payload={
                    "schema": "dtis.mobile-pairing.v1",
                    "status": "accepted",
                },
            )

        router.register(PAIRING_CLAIM_OPERATION, handle_claim)

        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            # Wait for and answer the auth challenge.
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, flags, payload = decode_aoa_frame(challenge_frame)
            self.assertEqual(request_id, AOA_AUTH_CHALLENGE_REQUEST_ID)
            self.assertEqual(flags, AOA_FRAME_FLAG_TEXT)
            challenge = json.loads(payload.decode("utf-8"))
            self.assertEqual(challenge["operation"], "transport.auth.challenge")
            rand = challenge["body"]["rand"]

            driver.inject_frame(
                encode_aoa_frame(
                    AOA_AUTH_CHALLENGE_REQUEST_ID,
                    _build_auth_response(rand, "123456", AOA_AUTH_CHALLENGE_REQUEST_ID),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            # Wait for the adapter to become authenticated.
            for _ in range(200):
                if adapter.state.value == "connected":
                    break
                time.sleep(0.01)
            self.assertEqual(adapter.state.value, "connected")

            # Send a pairing claim request and collect the response.
            claim_request = {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": PAIRING_CLAIM_OPERATION,
                "request_id": CLAIM_REQUEST_ID,
                "body_schema": "dtis.mobile-pairing.v1",
                "body": {
                    "schema": "dtis.mobile-pairing.v1",
                    "sid": "sid-001",
                    "opt": "123456",
                },
            }
            claim_payload = json.dumps(
                claim_request,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            driver.inject_frame(
                encode_aoa_frame(
                    CLAIM_REQUEST_ID,
                    claim_payload,
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            response: dict[str, object] | None = None
            for _ in range(300):
                response_frame = driver.read_frame(timeout=0.01)
                if response_frame:
                    response_request_id, response_flags, response_payload = decode_aoa_frame(
                        response_frame
                    )
                    if response_request_id == CLAIM_REQUEST_ID and response_flags == AOA_FRAME_FLAG_TEXT:
                        response = json.loads(response_payload.decode("utf-8"))
                        break
                time.sleep(0.01)

            self.assertIsNotNone(response)
            assert response is not None
            self.assertEqual(response["status_code"], 200)
            response_body = response["body"]
            self.assertIsInstance(response_body, dict)
            assert isinstance(response_body, dict)
            self.assertEqual(response_body["status"], "accepted")
        finally:
            adapter.stop()

    def test_claim_round_trip_with_unpadded_envelope_request_id(self) -> None:
        # The mobile frames requests with the request_id padded to 36 bytes while
        # the envelope keeps the unpadded id. The desktop must echo the 36-byte
        # frame id in the response frame and keep the unpadded id in the envelope.
        router = MobileTransportRouter()

        def handle_claim(request: MobileTransportRequest) -> MobileTransportResponse:
            payload = request.payload
            self.assertEqual(payload.get("sid"), "sid-001")
            return MobileTransportResponse(
                status_code=200,
                payload={
                    "schema": "dtis.mobile-pairing.v1",
                    "status": "accepted",
                },
            )

        router.register(PAIRING_CLAIM_OPERATION, handle_claim)

        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            challenge = json.loads(payload.decode("utf-8"))
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    _build_auth_response(challenge["body"]["rand"], "123456", request_id),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )
            for _ in range(200):
                if adapter.state.value == "connected":
                    break
                time.sleep(0.01)
            self.assertEqual(adapter.state.value, "connected")

            envelope_request_id = "claim-002"
            claim_request = {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": PAIRING_CLAIM_OPERATION,
                "request_id": envelope_request_id,
                "body_schema": "dtis.mobile-pairing.v1",
                "body": {
                    "schema": "dtis.mobile-pairing.v1",
                    "sid": "sid-001",
                    "opt": "123456",
                },
            }
            claim_payload = json.dumps(
                claim_request,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            driver.inject_frame(
                encode_aoa_frame(
                    envelope_request_id.ljust(36, " "),
                    claim_payload,
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            response: dict[str, object] | None = None
            for _ in range(300):
                response_frame = driver.read_frame(timeout=0.01)
                if response_frame:
                    response_frame_request_id, response_flags, response_payload = decode_aoa_frame(
                        response_frame
                    )
                    if response_flags != AOA_FRAME_FLAG_TEXT:
                        continue
                    parsed = json.loads(response_payload.decode("utf-8"))
                    if parsed.get("request_id") == envelope_request_id:
                        self.assertEqual(len(response_frame_request_id), 36)
                        response = parsed
                        break
                time.sleep(0.01)

            self.assertIsNotNone(response)
            assert response is not None
            self.assertEqual(response["status_code"], 200)
            self.assertEqual(response["request_id"], envelope_request_id)
        finally:
            adapter.stop()

    def test_auth_challenge_rejected_when_proof_is_wrong(self) -> None:
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            self.assertEqual(request_id, AOA_AUTH_CHALLENGE_REQUEST_ID)
            challenge = json.loads(payload.decode("utf-8"))
            rand = challenge["body"]["rand"]

            # Provide a deliberately wrong proof.
            bad_proof = hashlib.sha256(b"wrong").hexdigest()
            bad_response = {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "request_id": AOA_AUTH_CHALLENGE_REQUEST_ID,
                "status_code": 200,
                "body": {
                    "schema": "dtis.mobile-pairing.v1",
                    "status": "accepted",
                    "proof": bad_proof,
                },
            }
            driver.inject_frame(
                encode_aoa_frame(
                    AOA_AUTH_CHALLENGE_REQUEST_ID,
                    json.dumps(bad_response, separators=(",", ":"), sort_keys=True).encode(
                        "utf-8"
                    ),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            # Wait long enough for the auth challenge to time out/fail.
            connected = False
            for _ in range(100):
                if adapter.state.value == "connected":
                    connected = True
                    break
                if adapter.last_probe_error is not None:
                    break
                time.sleep(0.02)
            self.assertFalse(connected)
            self.assertIsNotNone(adapter.last_probe_error)
        finally:
            adapter.stop()

    def test_open_accessory_stream_retries_after_transient_disconnect(self) -> None:
        accessory = AoaDetectedDevice(
            device_id="dev-retry",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = _FlakyOpenAoaDriver(failures_before_success=2, accessory_device=accessory)
        adapter = UsbAoaTransportAdapter(
            router=MobileTransportRouter(),
            driver=driver,
            open_retry_attempts=3,
            open_retry_delay_seconds=0.0,
        )

        read_stream, write_stream = adapter._open_accessory_stream(accessory)

        self.assertEqual(driver.open_attempts, 3)
        self.assertIsInstance(read_stream, _StubAoaStream)
        self.assertIsInstance(write_stream, _StubAoaStream)

    def test_open_accessory_stream_raises_after_all_retries_fail(self) -> None:
        accessory = AoaDetectedDevice(
            device_id="dev-fail",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = _FlakyOpenAoaDriver(failures_before_success=99, accessory_device=accessory)
        adapter = UsbAoaTransportAdapter(
            router=MobileTransportRouter(),
            driver=driver,
            open_retry_attempts=3,
            open_retry_delay_seconds=0.0,
        )

        with self.assertRaises(RuntimeError):
            adapter._open_accessory_stream(accessory)

        self.assertEqual(driver.open_attempts, 3)

    def test_open_accessory_stream_succeeds_without_retry(self) -> None:
        accessory = AoaDetectedDevice(
            device_id="dev-ok",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = _FlakyOpenAoaDriver(failures_before_success=0, accessory_device=accessory)
        adapter = UsbAoaTransportAdapter(
            router=MobileTransportRouter(),
            driver=driver,
            open_retry_attempts=3,
            open_retry_delay_seconds=0.0,
        )

        read_stream, write_stream = adapter._open_accessory_stream(accessory)

        self.assertEqual(driver.open_attempts, 1)
        self.assertIsInstance(read_stream, _StubAoaStream)
        self.assertIsInstance(write_stream, _StubAoaStream)

    def test_open_accessory_stream_fails_fast_on_access_denied(self) -> None:
        accessory = AoaDetectedDevice(
            device_id="dev-perm",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = _AccessDeniedAoaDriver(accessory_device=accessory)
        adapter = UsbAoaTransportAdapter(
            router=MobileTransportRouter(),
            driver=driver,
            open_retry_attempts=3,
            open_retry_delay_seconds=0.0,
        )

        with self.assertRaises(RuntimeError) as error_context:
            adapter._open_accessory_stream(accessory)

        self.assertEqual(driver.open_attempts, 1)
        self.assertIn("Access denied", str(error_context.exception))

    def test_is_access_denied_error_detects_permission_denials(self) -> None:
        from dt_image_search.mobile.transport.usb_aoa_adapter import _is_access_denied_error

        self.assertTrue(
            _is_access_denied_error(
                RuntimeError("AOA stream setup failed at claim_interface: [Errno 13] Access denied (insufficient permissions)")
            )
        )
        self.assertTrue(_is_access_denied_error(RuntimeError("insufficient permissions")))
        self.assertFalse(_is_access_denied_error(RuntimeError("No such device (it may have been disconnected)")))

    def test_is_mobile_not_ready_error_detects_auth_timeout(self) -> None:
        from dt_image_search.mobile.transport.usb_aoa_adapter import _is_mobile_not_ready_error

        self.assertTrue(_is_mobile_not_ready_error(RuntimeError("Desktop AOA auth challenge timed out.")))
        self.assertFalse(_is_mobile_not_ready_error(RuntimeError("AOA stream write failed: [Errno 60] Operation timed out")))

    def test_driver_handle_is_released_after_session_ends(self) -> None:
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = _TrackingStopDriver(accessory_device=device)
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
            auth_challenge_timeout_seconds=0.2,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            # Answer the auth challenge with a wrong proof so the session fails and
            # the loop's finally block must release the driver handle.
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            challenge = json.loads(payload.decode("utf-8"))
            bad_response = {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "request_id": request_id,
                "status_code": 200,
                "body": {
                    "schema": "dtis.mobile-pairing.v1",
                    "status": "accepted",
                    "proof": hashlib.sha256(b"wrong").hexdigest(),
                },
            }
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    json.dumps(bad_response, separators=(",", ":"), sort_keys=True).encode("utf-8"),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            stop_seen = False
            for _ in range(200):
                if driver.stop_calls > 0:
                    stop_seen = True
                    break
                time.sleep(0.02)
            self.assertTrue(stop_seen, "driver.stop() was not called after the session ended")
        finally:
            adapter.stop()

    def test_session_failure_backoff_grows_then_resets(self) -> None:
        """Repeated session failures must back off the retry interval and reset on success."""
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="dev-backoff",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.01,
            response_poll_timeout_seconds=0.01,
            auth_challenge_timeout_seconds=0.05,
            max_session_failure_backoff_seconds=0.2,
        )

        # Without any failure, the wait equals the base probe interval.
        adapter._consecutive_session_failures = 0
        start = time.monotonic()
        adapter._wait_for_retry_interval()
        base_elapsed = time.monotonic() - start
        self.assertLess(base_elapsed, 0.05)

        # A few failures should push the wait past the base interval (backoff).
        adapter._consecutive_session_failures = 3
        start = time.monotonic()
        adapter._wait_for_retry_interval()
        backed_off_elapsed = time.monotonic() - start
        self.assertGreaterEqual(backed_off_elapsed, 0.02)
        self.assertLessEqual(backed_off_elapsed, 0.3)

        # A successful connection resets the failure counter.
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()
        try:
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            challenge = json.loads(payload.decode("utf-8"))
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    _build_auth_response(challenge["body"]["rand"], "123456", request_id),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )
            connected = False
            for _ in range(200):
                if adapter.state.value == "connected":
                    connected = True
                    break
                time.sleep(0.01)
            self.assertTrue(connected)
            self.assertEqual(adapter._consecutive_session_failures, 0)
        finally:
            adapter.stop()


    def test_auth_recovers_from_stale_stream_bytes(self) -> None:
        """The desktop must drain stale bytes from a desynchronized stream before
        the auth handshake instead of failing and re-probing forever."""
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        # Garbage that the desynchronized gadget would return on the first read.
        stale_bytes = b"\x00\x01\x02 stale bytes from a previous stream generation"
        driver = _StaleReadAoaDriver(accessory_device=device, stale_bytes=stale_bytes)
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(
                challenge_frame,
                "desktop must drain stale bytes and send an auth challenge "
                "instead of looping on 'Unsupported AOA frame version'",
            )
            request_id, flags, payload = decode_aoa_frame(challenge_frame)
            self.assertEqual(flags, AOA_FRAME_FLAG_TEXT)
            challenge = json.loads(payload.decode("utf-8"))
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    _build_auth_response(challenge["body"]["rand"], "123456", request_id),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )
            connected = False
            for _ in range(200):
                if adapter.state.value == "connected":
                    connected = True
                    break
                time.sleep(0.01)
            self.assertTrue(connected, "adapter must authenticate despite stale stream bytes")
        finally:
            adapter.stop()

    def test_session_stall_timeout_validation(self) -> None:
        """The session stall timeout must be positive when provided."""
        router = MobileTransportRouter()
        with self.assertRaises(ValueError):
            UsbAoaTransportAdapter(
                router=router,
                session_stall_timeout_seconds=0,
            )

    def test_session_loop_recovers_from_stalled_asset_upload(self) -> None:
        """A session with an in-flight asset upload that goes silent must be torn
        down and re-probed so the host can re-authenticate a fresh mobile stream.

        The mobile can be frozen by the OS (screen off / battery optimization)
        mid-upload. The desktop must not block forever in the read loop waiting
        for frames that never arrive; otherwise the transfer hangs permanently
        because the host never returns to the probe loop to re-authenticate.
        """
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
            session_stall_timeout_seconds=0.2,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            # Authenticate so the session reaches CONNECTED.
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            challenge = json.loads(payload.decode("utf-8"))
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    _build_auth_response(challenge["body"]["rand"], "123456", request_id),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )
            for _ in range(200):
                if adapter.state.value == "connected":
                    break
                time.sleep(0.01)
            self.assertEqual(adapter.state.value, "connected")

            # Arm an in-flight asset upload, then stop sending anything. The
            # desktop must notice the stalled upload and re-probe, which produces
            # a fresh auth challenge.
            asset_request_id = "asset-001".ljust(36, "0")
            asset_start = {
                "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                "operation": TRANSFER_ASSET_OPERATION,
                "request_id": "asset-001",
                "body_schema": "dtis.mobile-transfer.v1",
                "body": {
                    "schema": "dtis.mobile-transfer.v1",
                    "session_id": "sid-001",
                    "device_uuid": "dev-1",
                    "stream_state": "start",
                    "request_id": "asset-001",
                    "chunk_size": 262144,
                    "asset_id": "content://media/external/images/media/1",
                    "sha1": "0123456789abcdef0123456789abcdef01234567",
                    "file_size": 1000,
                    "created_at": "2026-08-10T21:53:50.000Z",
                },
            }
            driver.inject_frame(
                encode_aoa_frame(
                    asset_request_id,
                    json.dumps(asset_start, separators=(",", ":"), sort_keys=True).encode("utf-8"),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )

            # Expect the host to give up on the silent session and re-probe.
            # The simulated driver places a None sentinel in the queue when the
            # host stops the old stream, so skip non-bytes results while polling.
            reauth_frame: bytes | None = None
            deadline = time.monotonic() + 3.0
            while time.monotonic() < deadline and reauth_frame is None:
                frame = driver.read_frame(timeout=0.1)
                if frame:
                    reauth_frame = frame
            self.assertIsNotNone(
                reauth_frame,
                "desktop must re-probe after a stalled in-flight upload instead of blocking forever",
            )
            reauth_request_id, reauth_flags, _ = decode_aoa_frame(reauth_frame)
            self.assertEqual(reauth_request_id, AOA_AUTH_CHALLENGE_REQUEST_ID)
            self.assertEqual(reauth_flags, AOA_FRAME_FLAG_TEXT)
        finally:
            adapter.stop()

    def test_session_loop_keeps_idle_session_alive(self) -> None:
        """An idle but healthy session (no in-flight upload) must not be torn down
        by the stall detector."""
        router = MobileTransportRouter()
        device = AoaDetectedDevice(
            device_id="sim-device",
            vendor_id=0x18D1,
            product_id=0x2D01,
            serial_number="abc",
            is_accessory_mode=True,
        )
        driver = SimulatedAoaHostDriver([device])
        adapter = UsbAoaTransportAdapter(
            router=router,
            driver=driver,
            probe_interval_seconds=0.05,
            response_poll_timeout_seconds=0.05,
            session_stall_timeout_seconds=0.2,
        )
        adapter.configure_bootstrap(
            UsbBootstrapConfig(
                session_id="sid-001",
                one_time_passcode="123456",
                suggested_port=45000,
            )
        )
        adapter.start()

        try:
            challenge_frame = driver.read_frame(timeout=2.0)
            self.assertIsNotNone(challenge_frame)
            request_id, _, payload = decode_aoa_frame(challenge_frame)
            challenge = json.loads(payload.decode("utf-8"))
            driver.inject_frame(
                encode_aoa_frame(
                    request_id,
                    _build_auth_response(challenge["body"]["rand"], "123456", request_id),
                    flags=AOA_FRAME_FLAG_TEXT,
                )
            )
            for _ in range(200):
                if adapter.state.value == "connected":
                    break
                time.sleep(0.01)
            self.assertEqual(adapter.state.value, "connected")

            # Wait past the stall timeout with no frames at all: the idle session
            # must stay connected and no re-auth challenge may be produced.
            time.sleep(0.5)
            self.assertEqual(adapter.state.value, "connected")
            self.assertIsNone(driver.read_frame(timeout=0.3))
        finally:
            adapter.stop()


if __name__ == "__main__":
    unittest.main()
