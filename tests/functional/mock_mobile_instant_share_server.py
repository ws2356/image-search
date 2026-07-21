"""Mock mobile HTTP server for instant-share protocol endpoints.

Implements all 6 protocol endpoints with real DH key exchange and AES-GCM trust
session encryption, so the full first-share trust flow can be exercised end-to-end.
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import tempfile
import threading
import http.server
from pathlib import Path
from typing import Callable

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, x25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.x509.oid import NameOID
from datetime import datetime, timedelta, timezone


_TRUST_SESSION_INFO_PREFIX = b"dtis.instant-share.trust-session.v1"
_TRUST_SESSION_ENVELOPE_SCHEMA = "dtis.instant-share.trust-envelope.v1"
_TRUST_SESSION_NONCE_BYTES = 12
_TRUST_NONCE_BYTES = 32
_API_PREFIX = "/api/instant-share/v1"


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: str) -> bytes:
    normalized = value.strip()
    padding = "=" * (-len(normalized) % 4)
    return base64.urlsafe_b64decode((normalized + padding).encode("ascii"))


class MockMobileInstantShareHandler(http.server.BaseHTTPRequestHandler):
    """HTTP request handler implementing the instant-share mobile protocol endpoints."""

    server: MockMobileInstantShareServer  # type: ignore[assignment]

    def log_message(self, format: str, *args: object) -> None:
        pass  # Suppress default logging

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict[str, object]:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length > 0 else b""
        if not raw:
            return {}
        parsed = json.loads(raw.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError("Expected JSON object")
        return parsed

    def _decrypt_trust_envelope(self, body: dict[str, object]) -> dict[str, object]:
        """Decrypt an AES-GCM trust session envelope using the derived shared key."""
        if not isinstance(body.get("schema"), str) or body["schema"] != _TRUST_SESSION_ENVELOPE_SCHEMA:
            return body
        nonce = _base64url_decode(body["nonce"])
        ciphertext = _base64url_decode(body["ciphertext"])
        plaintext = AESGCM(self.server.session_key).decrypt(nonce, ciphertext, None)
        return json.loads(plaintext.decode("utf-8"))

    def _encrypt_trust_envelope(self, payload: dict[str, object]) -> dict[str, object]:
        """Encrypt a response payload with AES-GCM trust session envelope."""
        nonce = self.server.trust_session_nonce_provider(_TRUST_SESSION_NONCE_BYTES)
        plaintext = json.dumps(payload, separators=(",", ":"), sort_keys=True, ensure_ascii=False).encode("utf-8")
        ciphertext = AESGCM(self.server.session_key).encrypt(nonce, plaintext, None)
        return {
            "schema": _TRUST_SESSION_ENVELOPE_SCHEMA,
            "nonce": _base64url_encode(nonce),
            "ciphertext": _base64url_encode(ciphertext),
        }

    def do_POST(self) -> None:
        path = self.path.split("?")[0]
        route = path
        if route.startswith(_API_PREFIX):
            route = route[len(_API_PREFIX):]

        try:
            body = self._read_json_body()
        except Exception:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Invalid JSON body", "retryable": False})
            return

        if route == "/trust/handshake":
            self._handle_trust_handshake(body)
        elif route == "/trust/apply":
            self._handle_trust_apply(body)
        elif route == "/trust/confirm":
            self._handle_trust_confirm(body)
        elif route == "/payload/text":
            self._handle_payload_text()
        elif route == "/payload/image":
            self._handle_payload_image()
        elif route == "/delivery-result":
            self._handle_delivery_result(body)
        else:
            self._send_json(404, {"error_code": "INVALID_REQUEST", "message": f"Unknown route: {route}", "retryable": False})

    def _handle_trust_handshake(self, body: dict[str, object]) -> None:
        """DH handshake: receive PC's public key, return mobile's ephemeral public key."""
        pc_dh_public_key_b64 = body.get("pc_dh_public_key", "")
        pc_nonce_b64 = body.get("pc_nonce", "")

        if not pc_dh_public_key_b64 or not pc_nonce_b64:
            self._send_json(400, {"error_code": "INVALID_REQUEST", "message": "Missing DH keys", "retryable": False})
            return

        pc_public_key_bytes = _base64url_decode(str(pc_dh_public_key_b64))
        pc_nonce = _base64url_decode(str(pc_nonce_b64))

        # Generate mobile ephemeral DH keypair
        mobile_dh_private_key = x25519.X25519PrivateKey.generate()
        mobile_public_key_bytes = mobile_dh_private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        mobile_nonce = self.server.trust_session_nonce_provider(_TRUST_NONCE_BYTES)

        # Derive shared key
        pc_public_key = x25519.X25519PublicKey.from_public_bytes(pc_public_key_bytes)
        shared_secret = mobile_dh_private_key.exchange(pc_public_key)
        self.server.session_key = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=pc_nonce + mobile_nonce,
            info=_TRUST_SESSION_INFO_PREFIX + b"\x00" * 32,
        ).derive(shared_secret)

        self._send_json(200, {
            "mobile_dh_public_key": _base64url_encode(mobile_public_key_bytes),
            "mobile_nonce": _base64url_encode(mobile_nonce),
            "kdf_context": _base64url_encode(b"\x00" * 32),
        })

    def _handle_trust_apply(self, body: dict[str, object]) -> None:
        """Receive encrypted PIN apply payload."""
        self._decrypt_trust_envelope(body)
        self.server.pin_applied = True
        self._send_json(202, {"apply_status": "accepted"})

    def _handle_trust_confirm(self, body: dict[str, object]) -> None:
        """Return mobile public key after confirming PIN match."""
        self._decrypt_trust_envelope(body)
        response_payload = {
            "mobile_public_key_pem": self.server.mobile_public_key_pem,
            "trust_status": "trusted",
        }
        self._send_json(200, self._encrypt_trust_envelope(response_payload))

    def _handle_payload_text(self) -> None:
        """Return shared text payload."""
        self._send_json(200, {
            "state": "delivering",
            "text_utf8": self.server.shared_text,
        })

    def _handle_payload_image(self) -> None:
        """Return shared image bytes."""
        image_bytes = self.server.shared_image_bytes
        self.send_response(200)
        self.send_header("Content-Type", self.server.shared_image_content_type)
        self.send_header("Content-Length", str(len(image_bytes)))
        if self.server.shared_image_filename:
            self.send_header("X-Instant-Share-Filename", self.server.shared_image_filename)
        self.end_headers()
        self.wfile.write(image_bytes)

    def _handle_delivery_result(self, body: dict[str, object]) -> None:
        """Ack delivery result."""
        self.server.delivery_results.append(body)
        self._send_json(200, {"ack": True})


class _SslHttpServer(http.server.HTTPServer):
    """HTTPServer that wraps sockets with SSL."""

    def __init__(self, server_address, handler_class, ssl_context: ssl.SSLContext):
        super().__init__(server_address, handler_class)
        self.socket = ssl_context.wrap_socket(self.socket, server_side=True)


class MockMobileInstantShareServer:
    """Mock mobile HTTP server for instant-share protocol.

    Uses a single RSA key pair for both TLS and the trust-confirm identity key,
    so the PC client's TLS pin validation works against the mobile_public_key_pem
    returned from /trust/confirm.
    """

    def __init__(
        self,
        *,
        shared_text: str = "hello from mock ios",
        shared_image_bytes: bytes | None = None,
        shared_image_filename: str = "shared-photo.jpg",
        shared_image_content_type: str = "image/jpeg",
        trust_session_nonce_provider: Callable[[int], bytes] | None = None,
    ) -> None:
        self.shared_text = shared_text
        self.shared_image_bytes = shared_image_bytes or b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
        self.shared_image_filename = shared_image_filename
        self.shared_image_content_type = shared_image_content_type
        self.trust_session_nonce_provider = trust_session_nonce_provider or (lambda n: os.urandom(n))

        self.session_key: bytes | None = None
        self.pin_applied = False
        self.delivery_results: list[dict[str, object]] = []

        # Generate single RSA key pair for both TLS and identity
        self._rsa_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.mobile_public_key_pem = self._rsa_private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("utf-8")

        self._cert_path: Path | None = None
        self._key_path: Path | None = None
        self._httpd: _SslHttpServer | None = None
        self._thread: threading.Thread | None = None
        self._port: int = 0

    @property
    def port(self) -> int:
        return self._port

    @property
    def public_key_pem_for_tls_pin(self) -> str:
        """The public key PEM that the client should pin against (same as mobile_public_key_pem)."""
        return self.mobile_public_key_pem

    def start(self) -> int:
        """Start the mock server and return the port."""
        subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "mock-mobile.local")])
        certificate = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(self._rsa_private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(timezone.utc) - timedelta(minutes=1))
            .not_valid_after(datetime.now(timezone.utc) + timedelta(days=1))
            .sign(self._rsa_private_key, hashes.SHA256())
        )

        temp_dir = Path(tempfile.mkdtemp(prefix="mock_mobile_cert_"))
        self._cert_path = temp_dir / "mobile.pem"
        self._key_path = temp_dir / "mobile-key.pem"
        self._cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
        self._key_path.write_bytes(self._rsa_private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ))

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=str(self._cert_path), keyfile=str(self._key_path))

        self._httpd = _SslHttpServer(("127.0.0.1", 0), MockMobileInstantShareHandler, ssl_context)
        # Copy server state to httpd so handler can access it via self.server
        self._httpd.shared_text = self.shared_text
        self._httpd.shared_image_bytes = self.shared_image_bytes
        self._httpd.shared_image_filename = self.shared_image_filename
        self._httpd.shared_image_content_type = self.shared_image_content_type
        self._httpd.trust_session_nonce_provider = self.trust_session_nonce_provider
        self._httpd.session_key = None
        self._httpd.pin_applied = False
        self._httpd.delivery_results = self.delivery_results
        self._httpd.mobile_public_key_pem = self.mobile_public_key_pem
        self._port = self._httpd.server_address[1]

        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return self._port

    def stop(self) -> None:
        """Stop the mock server."""
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
        if self._cert_path is not None:
            try:
                self._cert_path.parent.rmdir()
            except OSError:
                pass
