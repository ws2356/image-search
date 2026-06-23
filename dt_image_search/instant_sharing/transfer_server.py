"""PC-side upload handler for the instant-share protocol.

In the pc-hosted-trust-and-upload architecture, the iOS client uploads
text and image payloads to the PC via /transfer/text and /transfer/image.
This module extracts the request body bytes and writes them to the
delivery service's inbound pipeline.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Callable, Mapping

from dt_image_search.instant_sharing.contracts import (
    DownloadedImagePayload,
    DownloadedTextPayload,
    ErrorCode,
    InstantShareMetadata,
    PayloadClass,
)
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.session import InstantShareSessionRegistry


_logger = logging.getLogger(__name__)


class TransferResult:
    """Result of a successful transfer from the iOS client."""

    def __init__(
        self,
        *,
        session_id: str,
        correlation_id: str,
        state: str,
        bytes_received: int,
        output_file_path: str = "",
    ) -> None:
        self._session_id = session_id
        self._correlation_id = correlation_id
        self._state = state
        self._bytes_received = bytes_received
        self._output_file_path = output_file_path

    @property
    def output_file_path(self) -> str:
        return self._output_file_path

    def as_dict(self) -> dict[str, object]:
        return {
            "session_id": self._session_id,
            "correlation_id": self._correlation_id,
            "state": self._state,
            "bytes_received": self._bytes_received,
            "accepted": True,
        }


class TransferHandler:
    """Handles incoming text/image uploads from the iOS client."""

    def __init__(
        self,
        *,
        session_registry: InstantShareSessionRegistry,
        delivery_service: InstantShareDeliveryService,
    ) -> None:
        self._session_registry = session_registry
        self._delivery_service = delivery_service

    def receive_text(
        self,
        *,
        session_id: str,
        correlation_id: str,
        body: bytes,
    ) -> TransferResult:
        session = self._session_registry.require_session(session_id)
        metadata = session.connection_config.metadata
        if metadata.payload_class not in (PayloadClass.TEXT, PayloadClass.LINK):
            raise InstantShareError(
                ErrorCode.DELIVERY_PATH_INVALID,
                f"Session {session_id} expects payload_class=image, got text.",
                correlation_id=correlation_id,
            )
        try:
            decoded = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                f"Failed to decode text payload: {exc}",
                correlation_id=correlation_id,
            ) from exc
        if not isinstance(decoded, dict):
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Text payload must be a JSON object.",
                correlation_id=correlation_id,
            )
        text_utf8 = str(decoded.get("text_utf8", ""))
        if not text_utf8:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Text payload is missing or empty text_utf8.",
                correlation_id=correlation_id,
            )
        text_payload = DownloadedTextPayload(metadata=metadata, text_utf8=text_utf8)
        result = self._delivery_service.deliver(text_payload)
        return TransferResult(
            session_id=session_id,
            correlation_id=correlation_id,
            state=result.state.value,
            bytes_received=len(body),
        )

    def receive_image(
        self,
        *,
        session_id: str,
        correlation_id: str,
        body: bytes | None = None,
        content_type: str | None,
        filename: str | None,
        temp_file_path: str | None = None,
    ) -> TransferResult:
        session = self._session_registry.require_session(session_id)
        metadata = session.connection_config.metadata
        if metadata.payload_class is not PayloadClass.IMAGE:
            raise InstantShareError(
                ErrorCode.DELIVERY_PATH_INVALID,
                f"Session {session_id} expects payload_class=text, got image.",
                correlation_id=correlation_id,
            )
        if session.image_count > 0 and session.received_count >= session.image_count:
            raise InstantShareError(
                ErrorCode.TRANSFER_LIMIT_EXCEEDED,
                f"Expected {session.image_count} images, but received more.",
                correlation_id=correlation_id,
            )
        if not body and not temp_file_path:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Image payload body is empty.",
                correlation_id=correlation_id,
            )
        image_payload = DownloadedImagePayload(
            metadata=metadata,
            image_bytes=body or b"",
            filename=filename,
            content_type=content_type or "application/octet-stream",
            manifest={},
            temp_file_path=temp_file_path,
        )
        result = self._delivery_service.deliver(image_payload)
        file_path = result.target_result.output_paths[0] if result.target_result.output_paths else ""
        bytes_received = body and len(body) or 0
        if temp_file_path:
            from pathlib import Path
            bytes_received = Path(temp_file_path).stat().st_size
        return TransferResult(
            session_id=session_id,
            correlation_id=correlation_id,
            state=result.state.value,
            bytes_received=bytes_received,
            output_file_path=file_path,
        )
