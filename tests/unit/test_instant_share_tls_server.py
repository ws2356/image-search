"""Tests for app-layer signature auth on the instant-share TLS server endpoints.

These tests exercise `_build_tls_app` with FastAPI's TestClient (no real TLS) to
verify that all `/transfer/*` endpoints require and validate the signature headers.
"""

from __future__ import annotations

import base64
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from cryptography import x509 as crypto_x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
import datetime
import ipaddress
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.contracts import (
    TRANSFER_DOWNLOAD_PATH,
    TRANSFER_IMAGE_PATH,
    TRANSFER_MANIFEST_PATH,
    TRANSFER_TEXT_PATH,
)
from dt_image_search.instant_sharing.https_bootstrap import _Deps
from dt_image_search.instant_sharing.https_tls_server import _build_tls_app
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry


class _FakeResult:
    def __init__(self, **kwargs: object) -> None:
        self._kwargs = kwargs

    def as_dict(self) -> dict[str, object]:
        return dict(self._kwargs)


class _FakeTransferHandler:
    def receive_text(self, **kwargs: object) -> _FakeResult:
        return _FakeResult(output_file_path="")

    def receive_image(self, **kwargs: object) -> _FakeResult:
        return _FakeResult(output_file_path="")


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _generate_mobile_cert(device_uuid: str) -> tuple[ec.EllipticCurvePrivateKey, str]:
    """Generate a P-256 ECDSA key + self-signed cert with a device UUID extension."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    subject = issuer = crypto_x509.Name([
        crypto_x509.NameAttribute(NameOID.COMMON_NAME, "iPhone"),
    ])
    device_id_oid = crypto_x509.ObjectIdentifier("2.25.37020860436019521")
    extensions = [
        crypto_x509.SubjectAlternativeName([crypto_x509.IPAddress(ipaddress.IPv4Address("127.0.0.1"))]),
        crypto_x509.UnrecognizedExtension(
            device_id_oid,
            device_uuid.encode("utf-8"),
        ),
    ]
    now = datetime.datetime.utcnow()
    cert = (
        crypto_x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(1)
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=365))
        .add_extension(extensions[0], critical=False)
        .add_extension(extensions[1], critical=False)
        .sign(private_key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    return private_key, cert_pem


class TestTLSServerSignatureAuth(unittest.TestCase):
    DEVICE_UUID = "ios-device-uuid-1234"
    SESSION_ID = "11111111-1111-1111-1111-111111111111"

    def setUp(self) -> None:
        self.private_key, self.cert_pem = _generate_mobile_cert(self.DEVICE_UUID)
        self.signature = _base64url_encode(
            self.private_key.sign(
                self.SESSION_ID.encode("utf-8"),
                ec.ECDSA(hashes.SHA256()),
            )
        )
        self.transfer_handler = _FakeTransferHandler()
        self.deps = _Deps(
            trust_session_registry=TrustSessionRegistry(),
            transfer_handler=self.transfer_handler,
            session_registry=MagicMock(),
            orchestrator=MagicMock(),
        )

    def _headers(self, *, session_id: str | None = None, signature: str | None = None) -> dict[str, str]:
        return {
            "X-Session-Id": session_id if session_id is not None else self.SESSION_ID,
            "X-Peer-Device-Id": self.DEVICE_UUID,
            "X-Session-Signature": signature if signature is not None else self.signature,
            "X-Session-Signature-Alg": "ecdsa-sha256",
        }

    def _patch_cert(self):
        return patch(
            "dt_image_search.instant_sharing.security.load_peer_certificate",
            return_value=self.cert_pem,
        )

    def test_transfer_text_without_signature_headers_returns_401(self) -> None:
        app = _build_tls_app(self.deps)
        with TestClient(app) as client:
            resp = client.post(TRANSFER_TEXT_PATH, json={"text_utf8": "hello"})
        self.assertEqual(resp.status_code, 401)

    def test_transfer_text_with_valid_signature_succeeds(self) -> None:
        app = _build_tls_app(self.deps)
        with TestClient(app) as client, self._patch_cert():
            resp = client.post(
                TRANSFER_TEXT_PATH,
                json={"text_utf8": "hello"},
                headers=self._headers(),
            )
        self.assertEqual(resp.status_code, 200)

    def test_transfer_image_with_invalid_signature_returns_401(self) -> None:
        app = _build_tls_app(self.deps)
        with TestClient(app) as client, self._patch_cert():
            resp = client.post(
                TRANSFER_IMAGE_PATH,
                content=b"\x89PNG\r\n\x1a\n",
                headers={
                    **self._headers(),
                    "Content-Type": "image/png",
                    "X-Session-Signature": _base64url_encode(b"\x00" * 64),
                },
            )
        self.assertEqual(resp.status_code, 401)
        self.assertEqual(resp.json()["error_code"], "SESSION_SIGNATURE_INVALID")

    def test_transfer_manifest_requires_signature(self) -> None:
        app = _build_tls_app(self.deps)
        with TestClient(app) as client, self._patch_cert():
            resp_no_sig = client.post(TRANSFER_MANIFEST_PATH, headers={"X-Session-Id": self.SESSION_ID})
            self.assertEqual(resp_no_sig.status_code, 401)

            resp_with_sig = client.post(
                TRANSFER_MANIFEST_PATH,
                headers=self._headers(),
            )
            self.assertEqual(resp_with_sig.status_code, 404)
            self.assertEqual(resp_with_sig.json()["error_code"], "SESSION_NOT_FOUND")

    def test_transfer_download_requires_signature(self) -> None:
        app = _build_tls_app(self.deps)
        with TestClient(app) as client, self._patch_cert():
            resp_no_sig = client.post(f"{TRANSFER_DOWNLOAD_PATH}/0", headers={"X-Session-Id": self.SESSION_ID})
            self.assertEqual(resp_no_sig.status_code, 401)

            resp_with_sig = client.post(
                f"{TRANSFER_DOWNLOAD_PATH}/0",
                headers=self._headers(),
            )
            self.assertEqual(resp_with_sig.status_code, 404)
            self.assertEqual(resp_with_sig.json()["error_code"], "SESSION_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
