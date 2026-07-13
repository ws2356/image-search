"""PC-side trust session manager for the instant-share protocol.

Supports two flows distinguished by TrustFlowType:

MOBILE_TO_PC:
  1. /trust/handshake (plain text DH exchange)
     - iOS sends mobile_dh_public_key, mobile_nonce
     - PC stores these, generates pc_nonce, kdf_context, returns pc_dh_public_key
     - Both sides derive the session key using HKDF-SHA256

  2. /trust/apply (encrypted PIN retrieval)
     - iOS sends encrypted {"action": "request_pin"}
     - PC generates a 4-digit PIN, stores it in session, returns an ack envelope
     - PC displays the PIN on screen; user reads it and enters it on the mobile

  3. /trust/confirm (encrypted finalization + device certificate exchange)
     - iOS sends encrypted {"action": "confirm", "pin_code": "<user-entered>", "device_certificate_pem": "..."}
     - PC verifies pin_code matches the stored PIN, stores mobile's certificate in keychain,
       returns encrypted {"trust_status": "trusted", "device_certificate_pem": "..."}
     - iOS stores PC's certificate in keychain

PC_TO_MOBILE (QR transfer):
  1. /trust/handshake (plain text DH exchange)
     - iOS sends mobile_dh_public_key, mobile_nonce (trust session already created by qr-trigger)
     - PC stores these, returns pc_dh_public_key, pc_nonce, kdf_context
     - Both sides derive the session key using HKDF-SHA256

  2. /trust/confirm (encrypted verification + device certificate exchange)
     - iOS sends encrypted {"action": "confirm", "opt_code": "<from-qr>", "device_certificate_pem": "..."}
     - PC verifies opt_code matches the stored code, stores mobile's certificate in keychain,
       returns encrypted {"trust_status": "trusted", "device_certificate_pem": "..."}
     - iOS stores PC's certificate in keychain
     - /trust/apply is skipped (opt_code already known to both sides from QR)
"""

from __future__ import annotations

import base64
import enum
import hmac
import logging
import os
import threading
import time
from typing import Any, Mapping

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import x25519

from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.security import (
    X25519TrustSessionKeyResolver,
    base64url_decode,
    compute_pairing_auth,
)
from dt_image_search.instant_sharing.trust_crypto import (
    TRUST_SESSION_ENVELOPE_SCHEMA,
    AesGcmTrustSessionProtector,
)


_logger = logging.getLogger(__name__)

ENCRYPTION_ALG = "aes-256-gcm"


class TrustFlowType(enum.Enum):
    MOBILE_TO_PC = "mobile_to_pc"
    PC_TO_MOBILE = "pc_to_mobile"


class TrustSession:
    """Per-session trust state held by the PC while the iOS client
    completes the handshake → (apply) → confirm sequence.

    In MOBILE_TO_PC flow the full 3-step handshake→apply→confirm
    sequence is followed.  In PC_TO_MOBILE flow /trust/apply is
    skipped (opt_code verification replaces PIN verification).
    """

    def __init__(
        self,
        *,
        session_id: str,
        correlation_id: str,
        flow_type: TrustFlowType,
        pc_key_resolver: X25519TrustSessionKeyResolver,
        pc_protector: AesGcmTrustSessionProtector,
        opt_code: str | None = None,
        stash_id: str | None = None,
    ) -> None:
        self._session_id = session_id
        self._correlation_id = correlation_id
        self._flow_type = flow_type
        self._pc_key_resolver = pc_key_resolver
        self._pc_protector = pc_protector
        self._mobile_dh_public_key: str | None = None
        self._mobile_dh_public_key_bytes: bytes | None = None
        self._mobile_nonce: str | None = None
        self._kdf_context: str | None = None
        self._pin_code: str | None = None
        self._opt_code: str | None = opt_code
        self._stash_id: str | None = stash_id
        self._mobile_certificate_pem: str | None = None
        self._peer_device_name: str = ""
        self._is_trusted = threading.Event()
        self._lock = threading.RLock()
        self._created_monotonic = time.monotonic()
        _logger.info(
            "[TrustSession] created session_id=%s flow_type=%s has_opt_code=%s has_stash_id=%s",
            session_id,
            flow_type.value,
            opt_code is not None,
            stash_id is not None,
        )

    @property
    def session_id(self) -> str:
        return self._session_id

    @property
    def correlation_id(self) -> str:
        return self._correlation_id

    @property
    def flow_type(self) -> TrustFlowType:
        return self._flow_type

    @property
    def pin_code(self) -> str | None:
        with self._lock:
            return self._pin_code

    @property
    def opt_code(self) -> str | None:
        with self._lock:
            return self._opt_code

    @property
    def stash_id(self) -> str | None:
        with self._lock:
            return self._stash_id

    @property
    def is_trusted(self) -> bool:
        return self._is_trusted.is_set()

    @property
    def is_session_key_established(self) -> bool:
        return self._pc_protector.is_established

    @property
    def mobile_certificate_pem(self) -> str | None:
        with self._lock:
            return self._mobile_certificate_pem

    @property
    def peer_device_name(self) -> str:
        with self._lock:
            return self._peer_device_name

    def set_peer_device_name(self, name: str) -> None:
        with self._lock:
            if self._peer_device_name:
                return
            self._peer_device_name = name

    def store_mobile_certificate(self, certificate_pem: str) -> None:
        with self._lock:
            self._mobile_certificate_pem = certificate_pem

    def store_mobile_handshake(
        self,
        *,
        mobile_dh_public_key: str,
        mobile_nonce: str,
    ) -> None:
        with self._lock:
            self._mobile_dh_public_key = mobile_dh_public_key
            self._mobile_dh_public_key_bytes = base64url_decode(
                mobile_dh_public_key, field_name="mobile_dh_public_key"
            )
            self._mobile_nonce = mobile_nonce

    def handshake_response(self) -> dict[str, str]:
        """Return the PC's handshake response (pc_dh_public_key, pc_nonce, kdf_context)."""
        handshake_request = self._pc_key_resolver.handshake_request_payload()
        return {
            "pc_dh_public_key": handshake_request["pc_dh_public_key"],
            "pc_nonce": handshake_request["pc_nonce"],
            "kdf_context": self._derive_kdf_context(),
        }

    def establish_session_key(self) -> None:
        """Derive the AES-GCM session key from the DH handshake exchange."""
        with self._lock:
            if self._mobile_dh_public_key is None or self._mobile_nonce is None:
                raise InstantShareError(
                    ErrorCode.HANDSHAKE_REQUIRED,
                    "Cannot establish session key before mobile handshake.",
                    correlation_id=self._correlation_id,
                )
            handshake_request = self._pc_key_resolver.handshake_request_payload()
            handshake_response = {
                "mobile_dh_public_key": self._mobile_dh_public_key,
                "mobile_nonce": self._mobile_nonce,
                "kdf_context": self._derive_kdf_context(),
            }
            self._pc_protector.establish_from_handshake(
                handshake_request=handshake_request,
                handshake_response=handshake_response,
            )

    def set_kdf_context(self, kdf_context: str) -> None:
        with self._lock:
            self._kdf_context = kdf_context

    def _derive_kdf_context(self) -> str:
        """Derive or return the cached kdf_context for this session."""
        with self._lock:
            if self._kdf_context is None:
                self._kdf_context = _base64url_encode(os.urandom(32))
            return self._kdf_context

    def decrypt_apply_request(self, envelope: Mapping[str, object]) -> dict[str, object]:
        """Decrypt and return the /trust/apply request body."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot decrypt apply request before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        return self._pc_protector.decrypt_json_payload(
            encrypted_payload=dict(envelope),
            correlation_id=self._correlation_id,
        )

    def decrypt_confirm_request(self, envelope: Mapping[str, object]) -> dict[str, object]:
        """Decrypt and return the /trust/confirm request body."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot decrypt confirm request before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        return self._pc_protector.decrypt_json_payload(
            encrypted_payload=dict(envelope),
            correlation_id=self._correlation_id,
        )

    def generate_pin(self) -> str:
        """Generate and store a 6-digit PIN for this session."""
        with self._lock:
            if self._pin_code is None:
                self._pin_code = _generate_pin_code()
            return self._pin_code

    def verify_pairing_auth(self, auth_b64: str) -> bool:
        with self._lock:
            if self._flow_type == TrustFlowType.PC_TO_MOBILE:
                short_secret = self._opt_code
            else:
                short_secret = self._pin_code
            if short_secret is None:
                return False
            if self._mobile_dh_public_key_bytes is None:
                return False
            return _verify_pairing_auth(
                auth_b64=auth_b64,
                short_secret=short_secret,
                pc_private_key_bytes=_extract_raw_private_key_bytes(
                    self._pc_key_resolver._private_key
                ),
                mobile_dh_public_key_bytes=self._mobile_dh_public_key_bytes,
                pc_dh_public_key_bytes=_extract_raw_public_key_bytes(
                    self._pc_key_resolver._private_key.public_key()
                ),
            )

    def verify_opt(self, opt_code: str) -> bool:
        """Legacy plaintext OPT comparison used by the WebRTC (DTLS-protected) path."""
        with self._lock:
            return self._opt_code is not None and self._opt_code == opt_code

    def encrypted_apply_ack_envelope(self) -> dict[str, str]:
        """Return an acknowledgment envelope (no PIN in the response)."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot encrypt apply ack before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        encrypted = self._pc_protector.encrypt_json_payload(
            payload={"status": "accepted"},
            correlation_id=self._correlation_id,
        )
        return {
            "schema": str(encrypted.get("schema", TRUST_SESSION_ENVELOPE_SCHEMA)),
            "nonce": str(encrypted.get("nonce", "")),
            "ciphertext": str(encrypted.get("ciphertext", "")),
            "encryption_alg": ENCRYPTION_ALG,
        }

    def encrypted_trust_status(self, *, pc_certificate_pem: str | None = None) -> dict[str, str]:
        """Return the trust status (+ optionally PC's device cert) encrypted in a trust envelope."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot encrypt trust status before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        payload: dict[str, str] = {"trust_status": "trusted"}
        if pc_certificate_pem is not None:
            payload["device_certificate_pem"] = pc_certificate_pem
        encrypted = self._pc_protector.encrypt_json_payload(
            payload=payload,
            correlation_id=self._correlation_id,
        )
        return {
            "schema": str(encrypted.get("schema", TRUST_SESSION_ENVELOPE_SCHEMA)),
            "nonce": str(encrypted.get("nonce", "")),
            "ciphertext": str(encrypted.get("ciphertext", "")),
            "encryption_alg": ENCRYPTION_ALG,
        }

    def mark_trusted(self) -> None:
        """Mark the trust session as trusted (after /trust/confirm succeeds)."""
        self._is_trusted.set()


class TrustSessionRegistry:
    """Holds active trust sessions for the PC receiver, keyed by session_id."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._sessions: dict[str, TrustSession] = {}
        self._cleanup_timers: dict[str, threading.Timer] = {}

    def create_session(
        self,
        *,
        session_id: str,
        correlation_id: str,
        flow_type: TrustFlowType = TrustFlowType.MOBILE_TO_PC,
        opt_code: str | None = None,
        stash_id: str | None = None,
    ) -> TrustSession:
        with self._lock:
            pc_key_resolver = X25519TrustSessionKeyResolver()
            pc_protector = AesGcmTrustSessionProtector(
                session_key_resolver=pc_key_resolver,
            )
            session = TrustSession(
                session_id=session_id,
                correlation_id=correlation_id,
                flow_type=flow_type,
                pc_key_resolver=pc_key_resolver,
                pc_protector=pc_protector,
                opt_code=opt_code,
                stash_id=stash_id,
            )
            self._sessions[session_id] = session
            _logger.info(
                "[TrustSessionRegistry] created trust session session_id=%s correlation_id=%s flow_type=%s",
                session_id,
                correlation_id,
                flow_type.value,
            )
            return session

    def get_session(self, session_id: str) -> TrustSession | None:
        with self._lock:
            return self._sessions.get(session_id)

    def require_session(self, session_id: str) -> TrustSession:
        session = self.get_session(session_id)
        if session is None:
            raise InstantShareError(
                ErrorCode.SESSION_ID_MISMATCH,
                "No active trust session matches the provided session id.",
            )
        return session

    def clear(self, session_id: str) -> None:
        with self._lock:
            self._cancel_cleanup_timer(session_id)
            session = self._sessions.pop(session_id, None)
            if session is not None:
                _logger.info(
                    "[TrustSessionRegistry] cleared trust session session_id=%s",
                    session_id,
                )

    def _schedule_cleanup(self, session_id: str) -> None:
        timer = threading.Timer(60.0, self._cleanup_session, args=[session_id])
        timer.daemon = True
        with self._lock:
            self._cleanup_timers[session_id] = timer
        timer.start()

    def _cleanup_session(self, session_id: str) -> None:
        with self._lock:
            self._sessions.pop(session_id, None)
            self._cleanup_timers.pop(session_id, None)

    def _cancel_cleanup_timer(self, session_id: str) -> None:
        timer = self._cleanup_timers.pop(session_id, None)
        if timer is not None:
            timer.cancel()


def _generate_pin_code() -> str:
    return f"{int.from_bytes(os.urandom(2), 'big') % 10000:04d}"


def _base64url_encode(data: bytes) -> str:
    import base64

    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _extract_raw_public_key_bytes(public_key: object) -> bytes:
    return public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )


def _extract_raw_private_key_bytes(private_key: object) -> bytes:
    return private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )


def _verify_pairing_auth(
    *,
    auth_b64: str,
    short_secret: str,
    pc_private_key_bytes: bytes,
    mobile_dh_public_key_bytes: bytes,
    pc_dh_public_key_bytes: bytes,
) -> bool:
    pc_private_key = x25519.X25519PrivateKey.from_private_bytes(pc_private_key_bytes)
    mobile_public_key = x25519.X25519PublicKey.from_public_bytes(mobile_dh_public_key_bytes)
    dh_shared_secret = pc_private_key.exchange(mobile_public_key)
    expected_auth = compute_pairing_auth(
        dh_shared_secret=dh_shared_secret,
        short_secret=short_secret,
        pc_dh_public_key=pc_dh_public_key_bytes,
        mobile_dh_public_key=mobile_dh_public_key_bytes,
    )
    return hmac.compare_digest(
        base64.urlsafe_b64decode(_pad_b64(auth_b64)),
        expected_auth,
    )


def _pad_b64(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return (value + padding).encode("ascii")
