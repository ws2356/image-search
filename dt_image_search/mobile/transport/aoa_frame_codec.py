#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AOA length-prefixed frame codec for Android Open Accessory USB transport.

Frames are structured as:
  [version:1][request_id:36][length:4][flags:1][payload]

version     : 1 byte, must be 0x01.
request_id  : 36 ASCII bytes (UUID without dashes, zero-padded, or any fixed 36-char id).
length      : 4 bytes, big-endian unsigned payload length.
flags       : 1 byte, 0x00 for text/JSON envelopes, 0x01 for binary asset chunks.
payload     : `length` bytes.
"""

from __future__ import annotations

AOA_FRAME_VERSION = 1
AOA_FRAME_HEADER_SIZE = 42
AOA_FRAME_FLAG_TEXT = 0x00
AOA_FRAME_FLAG_BINARY = 0x01
AOA_REQUEST_ID_LENGTH = 36


class AoaFrameError(ValueError):
    """Raised when a frame is malformed or unsupported."""


def encode_aoa_frame(
    request_id: str,
    payload: bytes,
    flags: int = AOA_FRAME_FLAG_TEXT,
) -> bytes:
    """Encode a single AOA frame.

    Args:
        request_id: Exactly 36 ASCII characters.
        payload: The raw payload bytes.
        flags: ``AOA_FRAME_FLAG_TEXT`` (default) or ``AOA_FRAME_FLAG_BINARY``.

    Returns:
        The complete frame bytes.
    """
    if not isinstance(request_id, str):
        raise AoaFrameError("request_id must be a string.")
    encoded_id = request_id.encode("ascii")
    if len(encoded_id) != AOA_REQUEST_ID_LENGTH:
        raise AoaFrameError(
            f"AOA frame request_id must be {AOA_REQUEST_ID_LENGTH} ASCII bytes, "
            f"got {len(encoded_id)}."
        )
    if flags not in (AOA_FRAME_FLAG_TEXT, AOA_FRAME_FLAG_BINARY):
        raise AoaFrameError(f"Unsupported AOA frame flags value: {flags}.")
    length = len(payload)
    if length > 0xFFFFFFFF:
        raise AoaFrameError("AOA frame payload exceeds 4 GB limit.")

    return (
        bytes([AOA_FRAME_VERSION])
        + encoded_id
        + length.to_bytes(4, byteorder="big", signed=False)
        + bytes([flags])
        + payload
    )


def decode_aoa_frame(data: bytes) -> tuple[str, int, bytes]:
    """Decode a single AOA frame.

    Args:
        data: A complete frame buffer.

    Returns:
        A tuple ``(request_id, flags, payload)``.

    Raises:
        AoaFrameError: If the frame is incomplete, malformed, or unsupported.
    """
    if len(data) < AOA_FRAME_HEADER_SIZE:
        raise AoaFrameError(
            f"AOA frame is too short for header ({len(data)} < {AOA_FRAME_HEADER_SIZE})."
        )
    if data[0] != AOA_FRAME_VERSION:
        raise AoaFrameError(f"Unsupported AOA frame version: {data[0]}.")

    request_id_bytes = data[1 : 1 + AOA_REQUEST_ID_LENGTH]
    try:
        request_id = request_id_bytes.decode("ascii")
    except UnicodeDecodeError as exc:
        raise AoaFrameError("AOA frame request_id is not valid ASCII.") from exc
    if len(request_id) != AOA_REQUEST_ID_LENGTH:
        raise AoaFrameError("AOA frame request_id length is invalid.")

    payload_length_start = 1 + AOA_REQUEST_ID_LENGTH
    payload_length_end = payload_length_start + 4
    declared_length = int.from_bytes(
        data[payload_length_start:payload_length_end],
        byteorder="big",
        signed=False,
    )
    flags = data[payload_length_end]
    if flags not in (AOA_FRAME_FLAG_TEXT, AOA_FRAME_FLAG_BINARY):
        raise AoaFrameError(f"Unsupported AOA frame flags value: {flags}.")

    payload = data[AOA_FRAME_HEADER_SIZE:]
    if len(payload) != declared_length:
        raise AoaFrameError(
            f"AOA frame payload length mismatch: declared {declared_length}, "
            f"actual {len(payload)}."
        )

    return request_id, flags, payload


class AoaFrameDecoder:
    """Incremental decoder for AOA frames.

    Feed bytes from a stream and receive complete ``(request_id, flags, payload)`` frames.
    """

    def __init__(self) -> None:
        self._buffer = bytearray()

    def reset(self) -> None:
        """Clear the internal buffer and reset decoder state."""
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[tuple[str, int, bytes]]:
        """Decode as many frames as possible from the new chunk.

        Args:
            data: A chunk of bytes from the stream.

        Returns:
            A list of complete ``(request_id, flags, payload)`` frames.

        Raises:
            AoaFrameError: If a frame header is malformed or unsupported.
        """
        self._buffer.extend(data)
        frames: list[tuple[str, int, bytes]] = []
        while True:
            if len(self._buffer) < AOA_FRAME_HEADER_SIZE:
                break

            if self._buffer[0] != AOA_FRAME_VERSION:
                raise AoaFrameError(
                    f"Unsupported AOA frame version: {self._buffer[0]}."
                )

            payload_length_start = 1 + AOA_REQUEST_ID_LENGTH
            payload_length_end = payload_length_start + 4
            declared_length = int.from_bytes(
                self._buffer[payload_length_start:payload_length_end],
                byteorder="big",
                signed=False,
            )
            total_frame_size = AOA_FRAME_HEADER_SIZE + declared_length
            if len(self._buffer) < total_frame_size:
                break

            frame = bytes(self._buffer[:total_frame_size])
            request_id, flags, payload = decode_aoa_frame(frame)
            frames.append((request_id, flags, payload))
            del self._buffer[:total_frame_size]

        return frames

    def __bytes__(self) -> bytes:
        """Return any unprocessed buffered bytes."""
        return bytes(self._buffer)
