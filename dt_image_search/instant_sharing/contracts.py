from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Mapping
from uuid import UUID


API_PREFIX = "/api/instant-share/v1"
PROTOCOL_VERSION = "1.0"
FLOW_ID = "instant_share"
BOOTSTRAP_PATH = f"{API_PREFIX}/sessions/bootstrap"


class PayloadClass(str, Enum):
    TEXT = "text"
    IMAGE = "image"


class TargetIntent(str, Enum):
    CLIPBOARD_ONLY = "clipboard_only"
    CLIPBOARD_OR_FILE = "clipboard_or_file"


class TrustMode(str, Enum):
    FIRST_SHARE = "first_share"
    TRUSTED_DIRECT = "trusted_direct"


class SessionState(str, Enum):
    BOOTSTRAPPED = "bootstrapped"
    QUEUED = "queued"
    NEGOTIATING = "negotiating"
    TRANSFERRING = "transferring"
    DELIVERING = "delivering"
    DONE = "done"
    FAILED = "failed"
    TIMED_OUT = "timed_out"
    ABORTED = "aborted"


class ErrorCode(str, Enum):
    RECEIVER_BUSY_SINGLE_SESSION = "RECEIVER_BUSY_SINGLE_SESSION"
    SESSION_ID_MISMATCH = "SESSION_ID_MISMATCH"
    SESSION_NOT_FOUND = "SESSION_NOT_FOUND"
    TARGET_INTENT_INVALID_FOR_PAYLOAD = "TARGET_INTENT_INVALID_FOR_PAYLOAD"
    HANDSHAKE_REQUIRED = "HANDSHAKE_REQUIRED"
    TRUST_REQUIRED = "TRUST_REQUIRED"
    PIN_MISMATCH_OR_REJECTED = "PIN_MISMATCH_OR_REJECTED"
    CONFIRM_TIMEOUT = "CONFIRM_TIMEOUT"
    SIGNATURE_VERIFICATION_FAILED = "SIGNATURE_VERIFICATION_FAILED"
    SESSION_SIGNATURE_INVALID = "SESSION_SIGNATURE_INVALID"
    TRUSTED_KEY_NOT_FOUND = "TRUSTED_KEY_NOT_FOUND"
    TLS_PIN_VALIDATION_FAILED = "TLS_PIN_VALIDATION_FAILED"
    PAYLOAD_UNREADABLE = "PAYLOAD_UNREADABLE"
    DELIVERY_PATH_INVALID = "DELIVERY_PATH_INVALID"
    TRANSFER_TIMEOUT = "TRANSFER_TIMEOUT"
    USER_ABORTED = "USER_ABORTED"
    PROTOCOL_VERSION_UNSUPPORTED = "PROTOCOL_VERSION_UNSUPPORTED"
    INVALID_REQUEST = "INVALID_REQUEST"
    HTTP_REQUEST_FAILED = "HTTP_REQUEST_FAILED"


TRUST_HANDSHAKE_PATH = f"{API_PREFIX}/trust/handshake"
TRUST_APPLY_PATH = f"{API_PREFIX}/trust/apply"
TRUST_CONFIRM_PATH = f"{API_PREFIX}/trust/confirm"
TRANSFER_TEXT_PATH = f"{API_PREFIX}/transfer/text"
TRANSFER_IMAGE_PATH = f"{API_PREFIX}/transfer/image"


_ALLOWED_TARGETS = {
    PayloadClass.TEXT: {TargetIntent.CLIPBOARD_ONLY},
    PayloadClass.IMAGE: {TargetIntent.CLIPBOARD_OR_FILE},
}
_TERMINAL_DELIVERY_STATES = {
    SessionState.DONE,
    SessionState.FAILED,
    SessionState.TIMED_OUT,
    SessionState.ABORTED,
}


def _normalize_uuid(value: str, *, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} must not be empty.")
    UUID(normalized)
    return normalized


@dataclass(frozen=True)
class InstantShareMetadata:
    payload_class: PayloadClass
    target_intent: TargetIntent
    trust_mode: TrustMode
    flow_id: str = FLOW_ID

    def validate(self) -> None:
        if self.flow_id != FLOW_ID:
            raise ValueError(f"flow_id must be {FLOW_ID}.")
        allowed_targets = _ALLOWED_TARGETS.get(self.payload_class, set())
        if self.target_intent not in allowed_targets:
            raise ValueError(
                f"target_intent={self.target_intent.value} is invalid for payload_class={self.payload_class.value}."
            )

    def as_dict(self) -> dict[str, str]:
        self.validate()
        return {
            "flow_id": self.flow_id,
            "payload_class": self.payload_class.value,
            "target_intent": self.target_intent.value,
            "trust_mode": self.trust_mode.value,
        }

    @classmethod
    def from_dict(cls, raw: Mapping[str, object]) -> "InstantShareMetadata":
        metadata = cls(
            flow_id=str(raw.get("flow_id", FLOW_ID)),
            payload_class=PayloadClass(str(raw.get("payload_class", ""))),
            target_intent=TargetIntent(str(raw.get("target_intent", ""))),
            trust_mode=TrustMode(str(raw.get("trust_mode", ""))),
        )
        metadata.validate()
        return metadata


@dataclass(frozen=True)
class InstantShareHeaders:
    correlation_id: str
    session_id: str
    device_id: str
    version: str = PROTOCOL_VERSION
    session_signature: str | None = None
    session_signature_algorithm: str | None = None

    def validate(self, *, requires_signature: bool) -> None:
        if self.version != PROTOCOL_VERSION:
            raise ValueError(f"Unsupported protocol version: {self.version}.")
        _normalize_uuid(self.correlation_id, field_name="correlation_id")
        _normalize_uuid(self.session_id, field_name="session_id")
        if not self.device_id.strip():
            raise ValueError("device_id must not be empty.")
        if requires_signature:
            if not self.session_signature or not self.session_signature.strip():
                raise ValueError("session_signature is required for this request.")
            if not self.session_signature_algorithm or not self.session_signature_algorithm.strip():
                raise ValueError("session_signature_algorithm is required for this request.")

    def as_http_headers(self, *, requires_signature: bool) -> dict[str, str]:
        self.validate(requires_signature=requires_signature)
        headers = {
            "X-Instant-Share-Version": self.version,
            "X-Correlation-Id": self.correlation_id,
            "X-Session-Id": self.session_id,
            "X-Device-Id": self.device_id,
        }
        if self.session_signature is not None:
            headers["X-Session-Signature"] = self.session_signature
        if self.session_signature_algorithm is not None:
            headers["X-Session-Signature-Alg"] = self.session_signature_algorithm
        return headers


@dataclass(frozen=True)
class DownloadedTextPayload:
    metadata: InstantShareMetadata
    text_utf8: str

    def as_dict(self) -> dict[str, object]:
        return {
            "metadata": self.metadata.as_dict(),
            "text_utf8": self.text_utf8,
        }


@dataclass(frozen=True)
class DownloadedImagePayload:
    metadata: InstantShareMetadata
    image_bytes: bytes
    filename: str | None = None
    content_type: str = "application/octet-stream"
    manifest: Mapping[str, object] = field(default_factory=dict)

    def as_dict(self) -> dict[str, object]:
        return {
            "metadata": self.metadata.as_dict(),
            "filename": self.filename,
            "content_type": self.content_type,
            "manifest": dict(self.manifest),
            "size_bytes": len(self.image_bytes),
        }


@dataclass(frozen=True)
class DeliveryTargetResult:
    clipboard_written: bool = False
    files_written_count: int = 0
    output_paths: tuple[str, ...] = ()

    def as_dict(self) -> dict[str, object]:
        return {
            "clipboard_written": self.clipboard_written,
            "files_written_count": self.files_written_count,
            "output_paths": list(self.output_paths),
        }


@dataclass(frozen=True)
class DeliveryResult:
    state: SessionState
    target_result: DeliveryTargetResult = field(default_factory=DeliveryTargetResult)
    error_code: str | None = None
    error_message: str | None = None

    def validate(self) -> None:
        if self.state not in _TERMINAL_DELIVERY_STATES:
            raise ValueError(f"delivery result state must be terminal, got {self.state.value}.")
        if self.state is SessionState.DONE:
            return
        if not self.error_code:
            raise ValueError("error_code is required for non-success delivery results.")

    def as_dict(self) -> dict[str, object]:
        self.validate()
        payload = {
            "state": self.state.value,
            "target_result": self.target_result.as_dict(),
        }
        if self.error_code is not None:
            payload["error_code"] = self.error_code
        if self.error_message is not None:
            payload["error_message"] = self.error_message
        return payload

    def to_json_bytes(self) -> bytes:
        return json.dumps(self.as_dict(), ensure_ascii=False).encode("utf-8")