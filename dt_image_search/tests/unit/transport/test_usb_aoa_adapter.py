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


if __name__ == "__main__":
    unittest.main()
