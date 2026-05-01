from __future__ import annotations

from collections.abc import Mapping
import base64
import hashlib
import json
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MOBILE_ENCRYPTION_SCHEMA = "dtis.mobile-encryption.v1"
MOBILE_ENCRYPTION_CAPABILITY = "encryption"
MOBILE_ENCRYPTED_BINARY_CHUNK_VERSION = 1
MOBILE_ENCRYPTED_BINARY_NONCE_BYTES = 12
MOBILE_ENCRYPTED_BINARY_TAG_BYTES = 16
MOBILE_ENCRYPTED_BINARY_CHUNK_OVERHEAD_BYTES = (
    1 + MOBILE_ENCRYPTED_BINARY_NONCE_BYTES + MOBILE_ENCRYPTED_BINARY_TAG_BYTES
)

_MOBILE_ENCRYPTION_KEY_DERIVATION_CONTEXT = "dtis.mobile-encryption.key.v1"


class MobilePayloadEncryptionError(ValueError):
    pass


def is_mobile_encrypted_payload(payload: object) -> bool:
    return (
        isinstance(payload, Mapping)
        and payload.get("schema") == MOBILE_ENCRYPTION_SCHEMA
    )


def derive_mobile_encryption_key(*, trust_key_b64: str) -> bytes:
    normalized_trust_key = trust_key_b64.strip()
    if not normalized_trust_key:
        raise MobilePayloadEncryptionError("Desktop rejected an empty mobile transfer trust key.")
    key_material = (
        f"{_MOBILE_ENCRYPTION_KEY_DERIVATION_CONTEXT}\n{normalized_trust_key}"
    ).encode("utf-8")
    return hashlib.sha256(key_material).digest()


def encrypt_mobile_json_payload(
    *,
    payload: Mapping[str, object],
    trust_key_b64: str,
    locator_fields: Mapping[str, str],
) -> dict[str, object]:
    key = derive_mobile_encryption_key(trust_key_b64=trust_key_b64)
    serialized_payload = json.dumps(
        dict(payload),
        separators=(",", ":"),
        sort_keys=True,
        ensure_ascii=False,
    ).encode("utf-8")
    nonce = os.urandom(MOBILE_ENCRYPTED_BINARY_NONCE_BYTES)
    ciphertext = AESGCM(key).encrypt(nonce, serialized_payload, None)
    encrypted_payload: dict[str, object] = {
        "schema": MOBILE_ENCRYPTION_SCHEMA,
        "nonce": _base64url_encode(nonce),
        "ciphertext": _base64url_encode(ciphertext),
    }
    for field_name, field_value in locator_fields.items():
        if not field_name.strip():
            raise MobilePayloadEncryptionError(
                "Desktop rejected an encrypted payload locator with an empty field name."
            )
        normalized_value = field_value.strip()
        if not normalized_value:
            raise MobilePayloadEncryptionError(
                f"Desktop rejected encrypted payload locator field '{field_name}'."
            )
        encrypted_payload[field_name] = normalized_value
    return encrypted_payload


def decrypt_mobile_json_payload(
    *,
    encrypted_payload: Mapping[str, object],
    trust_key_b64: str,
) -> dict[str, object]:
    if encrypted_payload.get("schema") != MOBILE_ENCRYPTION_SCHEMA:
        raise MobilePayloadEncryptionError(
            "Desktop received an unsupported encrypted payload schema."
        )
    nonce = _decode_required_base64url_field(encrypted_payload, "nonce")
    if len(nonce) != MOBILE_ENCRYPTED_BINARY_NONCE_BYTES:
        raise MobilePayloadEncryptionError(
            "Desktop rejected encrypted payload nonce length."
        )
    ciphertext = _decode_required_base64url_field(encrypted_payload, "ciphertext")
    key = derive_mobile_encryption_key(trust_key_b64=trust_key_b64)
    try:
        plaintext = AESGCM(key).decrypt(nonce, ciphertext, None)
    except Exception as exc:  # cryptography raises multiple internal exception types here.
        raise MobilePayloadEncryptionError(
            "Desktop could not decrypt the encrypted payload."
        ) from exc
    try:
        decoded_payload = json.loads(plaintext.decode("utf-8"))
    except Exception as exc:
        raise MobilePayloadEncryptionError(
            "Desktop decrypted an invalid encrypted payload JSON body."
        ) from exc
    if not isinstance(decoded_payload, dict):
        raise MobilePayloadEncryptionError(
            "Desktop decrypted an encrypted payload that is not a JSON object."
        )
    return decoded_payload


def encrypt_mobile_binary_chunk(*, chunk: bytes, trust_key_b64: str) -> bytes:
    key = derive_mobile_encryption_key(trust_key_b64=trust_key_b64)
    nonce = os.urandom(MOBILE_ENCRYPTED_BINARY_NONCE_BYTES)
    ciphertext = AESGCM(key).encrypt(nonce, chunk, None)
    return bytes([MOBILE_ENCRYPTED_BINARY_CHUNK_VERSION]) + nonce + ciphertext


def decrypt_mobile_binary_chunk(*, encrypted_chunk: bytes, trust_key_b64: str) -> bytes:
    if len(encrypted_chunk) < MOBILE_ENCRYPTED_BINARY_CHUNK_OVERHEAD_BYTES:
        raise MobilePayloadEncryptionError(
            "Desktop rejected encrypted transfer chunk framing."
        )
    chunk_version = encrypted_chunk[0]
    if chunk_version != MOBILE_ENCRYPTED_BINARY_CHUNK_VERSION:
        raise MobilePayloadEncryptionError(
            "Desktop rejected encrypted transfer chunk version."
        )
    nonce_end = 1 + MOBILE_ENCRYPTED_BINARY_NONCE_BYTES
    nonce = encrypted_chunk[1:nonce_end]
    ciphertext = encrypted_chunk[nonce_end:]
    key = derive_mobile_encryption_key(trust_key_b64=trust_key_b64)
    try:
        return AESGCM(key).decrypt(nonce, ciphertext, None)
    except Exception as exc:
        raise MobilePayloadEncryptionError(
            "Desktop could not decrypt transfer chunk."
        ) from exc


def _decode_required_base64url_field(
    payload: Mapping[str, object],
    field_name: str,
) -> bytes:
    raw_value = payload.get(field_name)
    if not isinstance(raw_value, str) or not raw_value.strip():
        raise MobilePayloadEncryptionError(
            f"Desktop rejected encrypted payload field '{field_name}'."
        )
    return _base64url_decode(raw_value.strip())


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: str) -> bytes:
    normalized_value = value.strip()
    if not normalized_value:
        raise MobilePayloadEncryptionError(
            "Desktop rejected encrypted payload because base64url value is empty."
        )
    padding = "=" * (-len(normalized_value) % 4)
    try:
        return base64.urlsafe_b64decode((normalized_value + padding).encode("ascii"))
    except Exception as exc:
        raise MobilePayloadEncryptionError(
            "Desktop rejected encrypted payload because base64url value is invalid."
        ) from exc
