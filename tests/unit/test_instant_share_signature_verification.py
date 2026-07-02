"""Tests for app-layer session signature verification (verify_session_signature).

Generates an ephemeral P-256 ECDSA key + self-signed certificate, signs a
session_id, and verifies that the public function in security.py correctly
validates (and rejects) signatures.
"""

from __future__ import annotations

import base64
import os
import sys
import unittest
from unittest.mock import patch, MagicMock

from cryptography import x509 as crypto_x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives.asymmetric import rsa
import datetime

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.security import verify_session_signature
from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def _generate_ecdsa_p256_cert(common_name: str) -> tuple[ec.EllipticCurvePrivateKey, str]:
    """Generate an ephemeral P-256 ECDSA key pair and a self-signed cert PEM."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()

    subject = issuer = crypto_x509.Name([
        crypto_x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ])
    now = datetime.datetime.utcnow()
    cert = (
        crypto_x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(public_key)
        .serial_number(1000)
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=365))
        .sign(private_key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    return private_key, cert_pem


def _sign_session_id(private_key: ec.EllipticCurvePrivateKey, session_id: str) -> str:
    """Sign a session_id with an ECDSA private key and return base64url-encoded signature."""
    signature_bytes = private_key.sign(
        session_id.encode("utf-8"),
        ec.ECDSA(hashes.SHA256()),
    )
    return _base64url_encode(signature_bytes)


class TestVerifySessionSignature(unittest.TestCase):
    """Tests for verify_session_signature with a P-256 ECDSA key."""

    SESSION_ID = "test-session-uuid"
    UNKNOWN_DEVICE = "nonexistent-device-uuid"

    def setUp(self) -> None:
        self.private_key, self.cert_pem = _generate_ecdsa_p256_cert("trusted-iphone")
        self.device_id = "trusted-device-uuid"
        self.valid_session_id = self.SESSION_ID
        self.valid_signature = _sign_session_id(self.private_key, self.valid_session_id)
        self.valid_algorithm = "ecdsa-sha256"

    def _patch_load_peer_certificate(self, return_value: str | None):
        """Patch load_peer_certificate to return the given PEM or None."""
        return patch(
            "dt_image_search.instant_sharing.security.load_peer_certificate",
            return_value=return_value,
        )

    # ---- Happy path ----

    def test_valid_signature_passes(self) -> None:
        """A correctly signed session_id should verify without raising."""
        with self._patch_load_peer_certificate(self.cert_pem):
            try:
                verify_session_signature(
                    self.device_id,
                    self.valid_session_id,
                    self.valid_signature,
                    self.valid_algorithm,
                )
            except InstantShareError:
                self.fail("verify_session_signature raised unexpectedly for valid input")

    # ---- Tampered data ----

    def test_tampered_session_id_fails(self) -> None:
        """Verification with a different session_id should raise SESSION_SIGNATURE_INVALID."""
        with self._patch_load_peer_certificate(self.cert_pem):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    self.device_id,
                    "tampered-session-id",
                    self.valid_signature,
                    self.valid_algorithm,
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)
        self.assertEqual(ctx.exception.status_code, 401)

    def test_tampered_signature_fails(self) -> None:
        """Verification with a tampered signature should raise SESSION_SIGNATURE_INVALID."""
        tampered_sig = _base64url_encode(b"\x00" * 64)
        with self._patch_load_peer_certificate(self.cert_pem):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    self.device_id,
                    self.valid_session_id,
                    tampered_sig,
                    self.valid_algorithm,
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)
        self.assertEqual(ctx.exception.status_code, 401)

    # ---- Unknown device ----

    def test_unknown_peer_device_id_fails(self) -> None:
        """Unknown device (no cert in keychain) should raise TRUSTED_KEY_NOT_FOUND."""
        with self._patch_load_peer_certificate(None):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    self.UNKNOWN_DEVICE,
                    self.valid_session_id,
                    self.valid_signature,
                    self.valid_algorithm,
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.TRUSTED_KEY_NOT_FOUND)
        self.assertEqual(ctx.exception.status_code, 403)

    # ---- Unsupported algorithm ----

    def test_unsupported_algorithm_fails(self) -> None:
        """An unsupported algorithm should raise SESSION_SIGNATURE_INVALID."""
        with self._patch_load_peer_certificate(self.cert_pem):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    self.device_id,
                    self.valid_session_id,
                    self.valid_signature,
                    "ed25519",
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)
        self.assertEqual(ctx.exception.status_code, 401)

    # ---- Non-EC public key rejection ----

    def test_non_ec_key_rejected(self) -> None:
        """A peer cert with an RSA key should cause verification to fail."""
        rsa_private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )
        subject = issuer = crypto_x509.Name([
            crypto_x509.NameAttribute(NameOID.COMMON_NAME, "rsa-device"),
        ])
        now = datetime.datetime.utcnow()
        cert = (
            crypto_x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(rsa_private_key.public_key())
            .serial_number(2000)
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=365))
            .sign(rsa_private_key, hashes.SHA256())
        )
        rsa_cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
        with self._patch_load_peer_certificate(rsa_cert_pem):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    "rsa-device",
                    self.valid_session_id,
                    self.valid_signature,
                    self.valid_algorithm,
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)
        self.assertEqual(ctx.exception.status_code, 401)

    # ---- Invalid base64 signature ----

    def test_invalid_base64_signature_fails(self) -> None:
        """A non-base64 signature should be caught and raise SESSION_SIGNATURE_INVALID."""
        with self._patch_load_peer_certificate(self.cert_pem):
            with self.assertRaises(InstantShareError) as ctx:
                verify_session_signature(
                    self.device_id,
                    self.valid_session_id,
                    "!!!not-base64!!!",
                    self.valid_algorithm,
                )
        self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)
        self.assertEqual(ctx.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
