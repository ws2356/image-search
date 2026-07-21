from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
from pathlib import Path
from typing import Mapping

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, x25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography import x509 as crypto_x509

from dt_image_search.identity import load_peer_certificate
from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError

_logger = logging.getLogger(__name__)


_TRUST_SESSION_INFO_PREFIX = b"dtis.instant-share.trust-session.v1"
_TRUST_NONCE_BYTES = 32
_PAIRING_PROTOCOL_CONTEXT = b"SnapGet Pairing v1"


def compute_pairing_auth(
    *,
    dh_shared_secret: bytes,
    short_secret: str,
    pc_dh_public_key: bytes,
    mobile_dh_public_key: bytes,
) -> bytes:
    master_secret = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=short_secret.encode("utf-8"),
        info=b"",
    ).derive(dh_shared_secret)
    transcript = _PAIRING_PROTOCOL_CONTEXT + pc_dh_public_key + mobile_dh_public_key
    return hmac.new(master_secret, transcript, hashlib.sha256).digest()


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def base64url_decode(value: object, *, field_name: str) -> bytes:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty base64url string.")
    normalized_value = value.strip()
    padding = "=" * (-len(normalized_value) % 4)
    return base64.urlsafe_b64decode((normalized_value + padding).encode("ascii"))


# Public alias kept for backward compatibility
_base64url_decode = base64url_decode


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
        mobile_public_key_bytes = base64url_decode(
            handshake_response.get("mobile_dh_public_key"),
            field_name="mobile_dh_public_key",
        )
        mobile_nonce = base64url_decode(
            handshake_response.get("mobile_nonce"),
            field_name="mobile_nonce",
        )
        kdf_context = base64url_decode(
            handshake_response.get("kdf_context"),
            field_name="kdf_context",
        )
        pc_nonce = base64url_decode(
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


def verify_session_signature(
    peer_device_id: str,
    session_id: str,
    signature: str,
    algorithm: str,
) -> None:
    """Verify an ECDSA-SHA256 signature of a session_id using a trusted peer's certificate.

    Args:
        peer_device_id: Unique identifier of the peer device.
        session_id: The session ID that was signed.
        signature: Base64url-encoded ECDSA-SHA256 signature.
        algorithm: Expected to be 'ecdsa-sha256'.

    Raises:
        InstantShareError(TRUSTED_KEY_NOT_FOUND): If no trusted peer cert found.
        InstantShareError(SESSION_SIGNATURE_INVALID): If algorithm is unsupported
            or signature verification fails.
    """
    SUPPORTED_ALGORITHM = "ecdsa-sha256"

    if algorithm != SUPPORTED_ALGORITHM:
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message=f"Unsupported signature algorithm: {algorithm}",
            status_code=401,
        )

    cert_pem = load_peer_certificate(peer_device_id)
    if cert_pem is None:
        _logger.error("no cert_pem for peer_device_id=%s", peer_device_id)
        raise InstantShareError(
            error_code=ErrorCode.TRUSTED_KEY_NOT_FOUND,
            message="No trusted peer certificate found for device",
            status_code=403,
        )

    try:
        cert = crypto_x509.load_pem_x509_certificate(cert_pem.encode("utf-8"))
    except Exception as exc:
        _logger.warning("Failed to parse peer certificate: %s", exc)
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message="Signature verification failed",
            status_code=401,
        ) from exc

    public_key = cert.public_key()
    if not isinstance(public_key, ec.EllipticCurvePublicKey):
        _logger.error("pub key not elliptic curve")
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message="Signature verification failed",
            status_code=401,
        )

    try:
        signature_bytes = base64url_decode(signature, field_name="signature")
    except (ValueError, TypeError) as exc:
        _logger.warning("Failed to base64url-decode signature: %s", exc)
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message="Signature verification failed",
            status_code=401,
        ) from exc

    try:
        public_key.verify(
            signature_bytes,
            session_id.encode("utf-8"),
            ec.ECDSA(hashes.SHA256()),
        )
        _logger.info(
            "Session signature verified for device=%s session_id=%s",
            peer_device_id, session_id,
        )
    except InvalidSignature:
        _logger.warning(
            "Session signature INVALID for device=%s session_id=%s",
            peer_device_id, session_id,
        )
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message="Signature verification failed",
            status_code=401,
        ) from None
    except Exception as exc:
        _logger.warning(
            "Session signature verification error for device=%s session_id=%s: %s",
            peer_device_id, session_id, exc,
        )
        raise InstantShareError(
            error_code=ErrorCode.SESSION_SIGNATURE_INVALID,
            message="Signature verification failed",
            status_code=401,
        ) from exc