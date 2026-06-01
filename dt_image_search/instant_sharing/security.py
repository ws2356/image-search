from __future__ import annotations

import base64
import os
from pathlib import Path
from typing import Mapping

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ed25519, x25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from dt_image_search.instant_sharing.ble import DeviceSignatureAdvertisement


_TRUST_SESSION_INFO_PREFIX = b"dtis.instant-share.trust-session.v1"
_TRUST_NONCE_BYTES = 32


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: object, *, field_name: str) -> bytes:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty base64url string.")
    normalized_value = value.strip()
    padding = "=" * (-len(normalized_value) % 4)
    return base64.urlsafe_b64decode((normalized_value + padding).encode("ascii"))


class X25519TrustSessionKeyResolver:
    def __init__(self, *, nonce_provider=os.urandom) -> None:
        self._private_key = x25519.X25519PrivateKey.generate()
        self._nonce = bytes(nonce_provider(_TRUST_NONCE_BYTES))
        if len(self._nonce) != _TRUST_NONCE_BYTES:
            raise ValueError("X25519 trust session resolver requires a 32-byte nonce.")

    def handshake_request_payload(self) -> dict[str, str]:
        public_key = self._private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        return {
            "pc_dh_public_key": _base64url_encode(public_key),
            "pc_nonce": _base64url_encode(self._nonce),
        }

    def __call__(
        self,
        *,
        handshake_request: Mapping[str, object],
        handshake_response: Mapping[str, object],
    ) -> bytes:
        mobile_public_key_bytes = _base64url_decode(
            handshake_response.get("mobile_dh_public_key"),
            field_name="mobile_dh_public_key",
        )
        mobile_nonce = _base64url_decode(
            handshake_response.get("mobile_nonce"),
            field_name="mobile_nonce",
        )
        kdf_context = _base64url_decode(
            handshake_response.get("kdf_context"),
            field_name="kdf_context",
        )
        pc_nonce = _base64url_decode(
            handshake_request.get("pc_nonce"),
            field_name="pc_nonce",
        )
        mobile_public_key = x25519.X25519PublicKey.from_public_bytes(mobile_public_key_bytes)
        shared_secret = self._private_key.exchange(mobile_public_key)
        return HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=pc_nonce + mobile_nonce,
            info=_TRUST_SESSION_INFO_PREFIX + kdf_context,
        ).derive(shared_secret)


class PersistentEd25519SessionSigner:
    def __init__(self, key_path: Path) -> None:
        self._key_path = key_path
        self._private_key = self._load_or_create_private_key(key_path)

    def sign(self, session_id: str) -> tuple[str, str]:
        if not isinstance(session_id, str) or not session_id:
            raise ValueError("session_id must not be empty.")
        signature = self._private_key.sign(session_id.encode("utf-8"))
        return (_base64url_encode(signature), "ed25519")

    def public_key_pem(self) -> str:
        return self._private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("utf-8")

    def device_signature_advertisement(self, *, device_id: str, timestamp_ms: int) -> DeviceSignatureAdvertisement:
        if not isinstance(device_id, str) or not device_id.strip():
            raise ValueError("device_id must not be empty.")
        if timestamp_ms <= 0:
            raise ValueError("timestamp_ms must be positive.")
        signed_message = f"{device_id}:{timestamp_ms}".encode("utf-8")
        signature = self._private_key.sign(signed_message)
        return DeviceSignatureAdvertisement(
            signature=_base64url_encode(signature),
            signature_key_id=device_id,
            timestamp_ms=timestamp_ms,
        )

    @staticmethod
    def _load_or_create_private_key(key_path: Path) -> ed25519.Ed25519PrivateKey:
        if key_path.exists():
            return serialization.load_pem_private_key(
                key_path.read_bytes(),
                password=None,
            )

        key_path.parent.mkdir(parents=True, exist_ok=True)
        private_key = ed25519.Ed25519PrivateKey.generate()
        pem_bytes = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        key_path.write_bytes(pem_bytes)
        try:
            os.chmod(key_path, 0o600)
        except OSError:
            pass
        return private_key