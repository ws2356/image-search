#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the AOA frame codec.

Author: deepseek-v4-flash-free
Date: 2026-08-01
"""

from __future__ import annotations

import unittest

from dt_image_search.mobile.transport.aoa_frame_codec import (
    AOA_FRAME_FLAG_BINARY,
    AOA_FRAME_FLAG_TEXT,
    AOA_FRAME_HEADER_SIZE,
    AOA_FRAME_VERSION,
    AOA_REQUEST_ID_LENGTH,
    AoaFrameDecoder,
    AoaFrameError,
    decode_aoa_frame,
    encode_aoa_frame,
)

REQUEST_ID = "12345678-1234-1234-1234-123456789012"


class TestEncodeDecodeAoaFrame(unittest.TestCase):
    def test_encode_and_decode_round_trip_text(self) -> None:
        payload = b"hello"
        frame = encode_aoa_frame(REQUEST_ID, payload)
        self.assertEqual(len(frame), AOA_FRAME_HEADER_SIZE + len(payload))
        decoded_request_id, decoded_flags, decoded_payload = decode_aoa_frame(frame)
        self.assertEqual(decoded_request_id, REQUEST_ID)
        self.assertEqual(decoded_flags, AOA_FRAME_FLAG_TEXT)
        self.assertEqual(decoded_payload, payload)

    def test_encode_and_decode_round_trip_binary(self) -> None:
        payload = bytes(range(256))
        frame = encode_aoa_frame(REQUEST_ID, payload, flags=AOA_FRAME_FLAG_BINARY)
        decoded_request_id, decoded_flags, decoded_payload = decode_aoa_frame(frame)
        self.assertEqual(decoded_request_id, REQUEST_ID)
        self.assertEqual(decoded_flags, AOA_FRAME_FLAG_BINARY)
        self.assertEqual(decoded_payload, payload)

    def test_encode_empty_payload(self) -> None:
        frame = encode_aoa_frame(REQUEST_ID, b"")
        self.assertEqual(len(frame), AOA_FRAME_HEADER_SIZE)
        request_id, flags, payload = decode_aoa_frame(frame)
        self.assertEqual((request_id, flags, payload), (REQUEST_ID, AOA_FRAME_FLAG_TEXT, b""))

    def test_encode_rejects_wrong_length_request_id(self) -> None:
        with self.assertRaises(AoaFrameError):
            encode_aoa_frame("short", b"x")

    def test_encode_rejects_non_ascii_request_id(self) -> None:
        with self.assertRaises(AoaFrameError):
            encode_aoa_frame("é" * 36, b"x")

    def test_encode_rejects_unsupported_flags(self) -> None:
        with self.assertRaises(AoaFrameError):
            encode_aoa_frame(REQUEST_ID, b"x", flags=0x02)

    def test_decode_rejects_too_short_frame(self) -> None:
        with self.assertRaises(AoaFrameError):
            decode_aoa_frame(b"x" * (AOA_FRAME_HEADER_SIZE - 1))

    def test_decode_rejects_unsupported_version(self) -> None:
        frame = bytearray(encode_aoa_frame(REQUEST_ID, b"x"))
        frame[0] = 0x02
        with self.assertRaises(AoaFrameError):
            decode_aoa_frame(bytes(frame))

    def test_decode_rejects_non_ascii_request_id(self) -> None:
        frame = bytearray(encode_aoa_frame(REQUEST_ID, b"x"))
        frame[1] = 0xFF
        with self.assertRaises(AoaFrameError):
            decode_aoa_frame(bytes(frame))

    def test_decode_rejects_unsupported_flags(self) -> None:
        frame = bytearray(encode_aoa_frame(REQUEST_ID, b"x"))
        frame[41] = 0x02
        with self.assertRaises(AoaFrameError):
            decode_aoa_frame(bytes(frame))

    def test_decode_rejects_payload_length_mismatch(self) -> None:
        frame = encode_aoa_frame(REQUEST_ID, b"abc")
        with self.assertRaises(AoaFrameError):
            decode_aoa_frame(frame[:-1])


class TestAoaFrameDecoder(unittest.TestCase):
    def test_decoder_recovers_from_partial_reads(self) -> None:
        decoder = AoaFrameDecoder()
        frame = encode_aoa_frame(REQUEST_ID, b"payload")
        self.assertEqual(decoder.feed(frame[:10]), [])
        self.assertEqual(decoder.feed(frame[10:25]), [])
        self.assertEqual(
            decoder.feed(frame[25:]),
            [(REQUEST_ID, AOA_FRAME_FLAG_TEXT, b"payload")],
        )

    def test_decoder_handles_multiple_frames_in_one_feed(self) -> None:
        decoder = AoaFrameDecoder()
        frame_one = encode_aoa_frame(REQUEST_ID, b"one")
        frame_two = encode_aoa_frame(REQUEST_ID, b"two")
        self.assertEqual(
            decoder.feed(frame_one + frame_two),
            [
                (REQUEST_ID, AOA_FRAME_FLAG_TEXT, b"one"),
                (REQUEST_ID, AOA_FRAME_FLAG_TEXT, b"two"),
            ],
        )

    def test_decoder_handles_frame_split_across_feeds(self) -> None:
        decoder = AoaFrameDecoder()
        frame = encode_aoa_frame(REQUEST_ID, b"split-payload")
        split_at = AOA_FRAME_HEADER_SIZE + 3
        self.assertEqual(decoder.feed(frame[:split_at]), [])
        self.assertEqual(
            decoder.feed(frame[split_at:]),
            [(REQUEST_ID, AOA_FRAME_FLAG_TEXT, b"split-payload")],
        )

    def test_decoder_preserves_remaining_bytes_after_frame(self) -> None:
        decoder = AoaFrameDecoder()
        frame = encode_aoa_frame(REQUEST_ID, b"x")
        decoder.feed(frame + b"leftover")
        self.assertEqual(bytes(decoder), b"leftover")

    def test_decoder_reset_clears_buffer(self) -> None:
        decoder = AoaFrameDecoder()
        decoder.feed(b"\x01partial")
        decoder.reset()
        self.assertEqual(bytes(decoder), b"")
        frame = encode_aoa_frame(REQUEST_ID, b"after-reset")
        self.assertEqual(decoder.feed(frame), [(REQUEST_ID, AOA_FRAME_FLAG_TEXT, b"after-reset")])

    def test_decoder_rejects_bad_version_in_header(self) -> None:
        decoder = AoaFrameDecoder()
        frame = bytearray(encode_aoa_frame(REQUEST_ID, b"x"))
        frame[0] = 0x09
        with self.assertRaises(AoaFrameError):
            decoder.feed(bytes(frame))


if __name__ == "__main__":
    unittest.main()
