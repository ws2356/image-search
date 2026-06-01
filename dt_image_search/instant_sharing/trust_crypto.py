from __future__ import annotations

import base64
import json
import os
from collections.abc import Mapping
from typing import Callable, Protocol

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError


TRUST_SESSION_ENVELOPE_SCHEMA = "dtis.instant-share.trust-envelope.v1"
_TRUST_SESSION_NONCE_BYTES = 12


class TrustSessionProtector(Protocol):
    @property
    def is_established(self) -> bool:
        ...

    def establish_from_handshake(
        self,
        *,
        handshake_request: Mapping[str, object],
        handshake_response: Mapping[str, object],
    ) -> None:
        ...

    def encrypt_json_payload(
        self,
        *,
        payload: Mapping[str, object],
        correlation_id: str,
    ) -> dict[str, object]:
        ...

    def decrypt_json_payload(
        self,
        *,
        encrypted_payload: Mapping[str, object],
        correlation_id: str,
    ) -> dict[str, object]:
        ...


def is_trust_session_envelope(payload: object) -> bool:
    return isinstance(payload, Mapping) and payload.get("schema") == TRUST_SESSION_ENVELOPE_SCHEMA


class AesGcmTrustSessionProtector:
    def __init__(
        self,
        *,
        session_key_resolver: Callable[..., bytes],
        nonce_provider: Callable[[int], bytes] = os.urandom,
    ) -> None:
        self._session_key_resolver = session_key_resolver
        self._nonce_provider = nonce_provider
        self._session_key: bytes | None = None

    @property
    def is_established(self) -> bool:
        return self._session_key is not None

    def establish_from_handshake(
        self,
        *,
        handshake_request: Mapping[str, object],
        handshake_response: Mapping[str, object],
    ) -> None:
        try:
            resolved_key = bytes(
                self._session_key_resolver(
                    handshake_request=dict(handshake_request),
                    handshake_response=dict(handshake_response),
                )
            )
        except Exception as exc:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Instant-share trust session protector could not derive a shared key from /trust/handshake.",
            ) from exc

        if len(resolved_key) not in {16, 24, 32}:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Instant-share trust session protector requires a 128/192/256-bit AES key.",
            )
        self._session_key = resolved_key

    def encrypt_json_payload(
        self,
        *,
        payload: Mapping[str, object],
        correlation_id: str,
    ) -> dict[str, object]:
        session_key = self._require_session_key(correlation_id=correlation_id)
        nonce = self._nonce_provider(_TRUST_SESSION_NONCE_BYTES)
        if len(nonce) != _TRUST_SESSION_NONCE_BYTES:
            raise InstantShareError(
                ErrorCode.INVALID_REQUEST,
                "Instant-share trust session protector received an invalid AES-GCM nonce.",
                correlation_id=correlation_id,
            )

        plaintext = json.dumps(
            dict(payload),
            separators=(",", ":"),
            sort_keys=True,
            ensure_ascii=False,
        ).encode("utf-8")
        ciphertext = AESGCM(session_key).encrypt(nonce, plaintext, None)
        return {
            "schema": TRUST_SESSION_ENVELOPE_SCHEMA,
            "nonce": _base64url_encode(nonce),
            "ciphertext": _base64url_encode(ciphertext),
        }

    def decrypt_json_payload(
        self,
        *,
        encrypted_payload: Mapping[str, object],
        correlation_id: str,
    ) -> dict[str, object]:
        session_key = self._require_session_key(correlation_id=correlation_id)
        if not is_trust_session_envelope(encrypted_payload):
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share trust response is not a supported encrypted envelope.",
                correlation_id=correlation_id,
            )

        nonce = _decode_required_base64url_field(
            encrypted_payload=encrypted_payload,
            field_name="nonce",
            correlation_id=correlation_id,
        )
        if len(nonce) != _TRUST_SESSION_NONCE_BYTES:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share trust response nonce length is invalid.",
                correlation_id=correlation_id,
            )
        ciphertext = _decode_required_base64url_field(
            encrypted_payload=encrypted_payload,
            field_name="ciphertext",
            correlation_id=correlation_id,
        )

        try:
            plaintext = AESGCM(session_key).decrypt(nonce, ciphertext, None)
        except Exception as exc:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share trust response could not be decrypted.",
                correlation_id=correlation_id,
            ) from exc

        try:
            decoded_payload = json.loads(plaintext.decode("utf-8"))
        except Exception as exc:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share trust response decrypted to invalid JSON.",
                correlation_id=correlation_id,
            ) from exc
        if not isinstance(decoded_payload, dict):
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share trust response decrypted to a non-object JSON payload.",
                correlation_id=correlation_id,
            )
        return decoded_payload

    def _require_session_key(self, *, correlation_id: str) -> bytes:
        if self._session_key is None:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Instant-share trust session protector requires a completed /trust/handshake first.",
                correlation_id=correlation_id,
            )
        return self._session_key


def _decode_required_base64url_field(
    *,
    encrypted_payload: Mapping[str, object],
    field_name: str,
    correlation_id: str,
) -> bytes:
    raw_value = encrypted_payload.get(field_name)
    if not isinstance(raw_value, str) or not raw_value.strip():
        raise InstantShareError(
            ErrorCode.PAYLOAD_UNREADABLE,
            f"Instant-share trust response field '{field_name}' is missing.",
            correlation_id=correlation_id,
        )
    return _base64url_decode(raw_value.strip(), correlation_id=correlation_id)


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: str, *, correlation_id: str) -> bytes:
    normalized_value = value.strip()
    if not normalized_value:
        raise InstantShareError(
            ErrorCode.PAYLOAD_UNREADABLE,
            "Instant-share trust response contains an empty base64url field.",
            correlation_id=correlation_id,
        )
    padding = "=" * (-len(normalized_value) % 4)
    try:
        return base64.urlsafe_b64decode((normalized_value + padding).encode("ascii"))
    except Exception as exc:
        raise InstantShareError(
            ErrorCode.PAYLOAD_UNREADABLE,
            "Instant-share trust response contains an invalid base64url field.",
            correlation_id=correlation_id,
        ) from exc