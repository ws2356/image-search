"""PC-side trust session manager for the instant-share protocol.

In the pc-hosted-trust-and-upload architecture, the trust flow is:

1. /trust/handshake (plain text DH exchange)
   - iOS sends mobile_dh_public_key, mobile_nonce
   - PC stores these, generates pc_nonce, kdf_context, returns pc_dh_public_key
   - Both sides derive the session key using HKDF-SHA256

2. /trust/apply (encrypted PIN retrieval)
   - iOS sends encrypted {"action": "request_pin"}
   - PC generates a 6-digit PIN, encrypts it, returns the envelope
   - Both sides display the same PIN

3. /trust/confirm (encrypted finalization, mobile-side only)
   - iOS sends encrypted {"action": "confirm", "pin_verified": true}
   - PC marks the trust session as trusted, returns encrypted {"trust_status": "trusted"}
   - No long-polling - iOS sends after user taps Confirm in iOS UI
"""

from __future__ import annotations

import logging
import os
import threading
import time
from typing import Any, Mapping

from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.security import X25519TrustSessionKeyResolver
from dt_image_search.instant_sharing.trust_crypto import (
    TRUST_SESSION_ENVELOPE_SCHEMA,
    AesGcmTrustSessionProtector,
)


_logger = logging.getLogger(__name__)

ENCRYPTION_ALG = "aes-256-gcm"


class TrustSession:
    """Per-session trust state held by the PC while the iOS client
    completes the handshake → apply → confirm sequence."""

    def __init__(
        self,
        *,
        session_id: str,
        correlation_id: str,
        pc_key_resolver: X25519TrustSessionKeyResolver,
        pc_protector: AesGcmTrustSessionProtector,
    ) -> None:
        self._session_id = session_id
        self._correlation_id = correlation_id
        self._pc_key_resolver = pc_key_resolver
        self._pc_protector = pc_protector
        self._mobile_dh_public_key: str | None = None
        self._mobile_nonce: str | None = None
        self._kdf_context: str | None = None
        self._pin_code: str | None = None
        self._is_trusted = threading.Event()
        self._lock = threading.RLock()
        self._created_monotonic = time.monotonic()

    @property
    def session_id(self) -> str:
        return self._session_id

    @property
    def correlation_id(self) -> str:
        return self._correlation_id

    @property
    def pin_code(self) -> str | None:
        with self._lock:
            return self._pin_code

    @property
    def is_trusted(self) -> bool:
        return self._is_trusted.is_set()

    @property
    def is_session_key_established(self) -> bool:
        return self._pc_protector.is_established

    def store_mobile_handshake(
        self,
        *,
        mobile_dh_public_key: str,
        mobile_nonce: str,
    ) -> None:
        with self._lock:
            self._mobile_dh_public_key = mobile_dh_public_key
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

    def encrypted_pin_envelope(self) -> dict[str, str]:
        """Return the PIN encrypted in a trust envelope."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot encrypt PIN before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        pin = self.pin_code
        if pin is None:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot encrypt PIN before PIN is generated.",
                correlation_id=self._correlation_id,
            )
        encrypted = self._pc_protector.encrypt_json_payload(
            payload={"pin_code": pin},
            correlation_id=self._correlation_id,
        )
        return {
            "schema": str(encrypted.get("schema", TRUST_SESSION_ENVELOPE_SCHEMA)),
            "nonce": str(encrypted.get("nonce", "")),
            "ciphertext": str(encrypted.get("ciphertext", "")),
            "encryption_alg": ENCRYPTION_ALG,
        }

    def encrypted_trust_status(self) -> dict[str, str]:
        """Return the trust status encrypted in a trust envelope."""
        if not self._pc_protector.is_established:
            raise InstantShareError(
                ErrorCode.HANDSHAKE_REQUIRED,
                "Cannot encrypt trust status before trust session key is established.",
                correlation_id=self._correlation_id,
            )
        encrypted = self._pc_protector.encrypt_json_payload(
            payload={"trust_status": "trusted"},
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
    """Holds the single active trust session for the PC receiver."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._session: TrustSession | None = None

    def create_session(
        self,
        *,
        session_id: str,
        correlation_id: str,
    ) -> TrustSession:
        with self._lock:
            pc_key_resolver = X25519TrustSessionKeyResolver()
            pc_protector = AesGcmTrustSessionProtector(
                session_key_resolver=pc_key_resolver,
            )
            session = TrustSession(
                session_id=session_id,
                correlation_id=correlation_id,
                pc_key_resolver=pc_key_resolver,
                pc_protector=pc_protector,
            )
            self._session = session
            _logger.info(
                "[TrustSessionRegistry] created trust session session_id=%s correlation_id=%s",
                session_id,
                correlation_id,
            )
            return session

    def get_session(self, session_id: str) -> TrustSession | None:
        with self._lock:
            if self._session is None:
                return None
            if self._session.session_id != session_id:
                return None
            return self._session

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
            if self._session is not None and self._session.session_id == session_id:
                _logger.info(
                    "[TrustSessionRegistry] cleared trust session session_id=%s",
                    session_id,
                )
                self._session = None


def _generate_pin_code() -> str:
    return f"{int.from_bytes(os.urandom(3), 'big') % 1000000:06d}"


def _base64url_encode(data: bytes) -> str:
    import base64

    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")
