from __future__ import annotations

import subprocess
import sys
import threading
from concurrent.futures import Future
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

from dt_image_search.model.dt_device_id import get_device_id

if sys.platform != "darwin":
    raise ImportError(
        "dt_image_search.identity is currently only supported on macOS. "
        f"Unsupported platform: {sys.platform}"
    )

_KEYCHAIN_SERVICE = "net.boldman.ausearch.device-identity"
_KEYCHAIN_ACCOUNT = "device-identity-v1"
_CERT_VALIDITY_YEARS = 20
_KEYCHAIN_PATH = Path.home() / "Library" / "Keychains" / "ausearch.keychain"
_KEY_CHAIN_PASSWORD = "123456"


def _resolve_keychain_path() -> Path:
    p = _KEYCHAIN_PATH
    if p.exists():
        return p
    db_p = p.with_suffix(".keychain-db")
    if db_p.exists():
        return db_p
    return p


_identity_future: Future[DeviceIdentity] | None = None
_lock = threading.Lock()


def _keychain_arg() -> list[str]:
    return [str(_resolve_keychain_path())]


def _ensure_keychain() -> None:
    p = _resolve_keychain_path()
    _KEYCHAIN_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not p.exists():
        subprocess.run(
            ["security", "create-keychain", "-p", _KEY_CHAIN_PASSWORD, str(_KEYCHAIN_PATH)],
            check=True, capture_output=True,
        )
        p = _resolve_keychain_path()
    subprocess.run(
        ["security", "unlock-keychain", "-p", _KEY_CHAIN_PASSWORD, str(p)],
        check=True, capture_output=True,
    )
    p.chmod(0o600)
    subprocess.run(
        ["security", "set-keychain-settings", "-u", str(p)],
        check=True, capture_output=True,
    )


@dataclass(frozen=True)
class DeviceIdentity:
    device_id: str
    certificate_pem: str
    private_key: ec.EllipticCurvePrivateKey


def initialize_device_identity() -> Future[DeviceIdentity]:
    global _identity_future
    if _identity_future is not None:
        return _identity_future

    with _lock:
        if _identity_future is not None:
            return _identity_future
        future: Future[DeviceIdentity] = Future()
        _identity_future = future

    def _run():
        try:
            identity = _load_or_create_identity()
            future.set_result(identity)
        except Exception as exc:
            future.set_exception(exc)

    t = threading.Thread(target=_run, daemon=True, name="device-identity-init")
    t.start()
    return _identity_future


def get_identity_future() -> Future[DeviceIdentity]:
    if _identity_future is None:
        raise RuntimeError(
            "Device identity not initialized. "
            "Call initialize_device_identity() first."
        )
    return _identity_future


def _load_or_create_identity() -> DeviceIdentity:
    _ensure_keychain()
    device_id = get_device_id()

    p12_data = _load_p12_from_keychain()
    if p12_data is not None:
        return _decode_identity(p12_data, device_id)

    identity = _generate_identity(device_id)
    p12_data = pkcs12.serialize_key_and_certificates(
        name=b"AuSearch Device Identity",
        key=identity.private_key,
        cert=x509.load_pem_x509_certificate(
            identity.certificate_pem.encode("utf-8")
        ),
        cas=None,
        encryption_algorithm=serialization.NoEncryption(),
    )
    _store_p12_to_keychain(p12_data)
    return identity


def _load_p12_from_keychain() -> bytes | None:
    try:
        result = subprocess.run(
            [
                "security", "find-generic-password",
                "-s", _KEYCHAIN_SERVICE,
                "-a", _KEYCHAIN_ACCOUNT,
                "-w",
                *_keychain_arg(),
            ],
            capture_output=True,
            check=True,
        )
        return bytes.fromhex(result.stdout.decode("utf-8").strip())
    except subprocess.CalledProcessError:
        return None


def _store_p12_to_keychain(p12_data: bytes) -> None:
    subprocess.run(
        [
            "security", "add-generic-password",
            "-s", _KEYCHAIN_SERVICE,
            "-a", _KEYCHAIN_ACCOUNT,
            "-l", "AuSearch Device Identity",
            "-U",
            "-w", p12_data.hex(),
            *_keychain_arg(),
        ],
        check=True,
    )


def _decode_identity(p12_data: bytes, device_id: str) -> DeviceIdentity:
    key, cert, _ = pkcs12.load_key_and_certificates(
        p12_data, password=None
    )
    if key is None or cert is None:
        raise ValueError(
            "Keychain P12 data is missing private key or certificate"
        )
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise TypeError(
            f"Expected ECDSA key in keychain, got {type(key).__name__}"
        )
    return DeviceIdentity(
        device_id=device_id,
        certificate_pem=cert.public_bytes(
            serialization.Encoding.PEM
        ).decode("utf-8"),
        private_key=key,
    )


_PEER_CERT_LABEL = "AuSearch Trusted Device"


def get_device_certificate_pem(timeout: float | None = 5.0) -> str:
    """Return this device's own certificate PEM, blocking until identity is ready."""
    future = get_identity_future()
    identity = future.result(timeout=timeout)
    return identity.certificate_pem


def store_peer_certificate(peer_device_id: str, certificate_pem: str) -> None:
    """Store a peer device's X.509 certificate in the dedicated keychain.

    Uses label "AuSearch Trusted Device" for future bulk queries.
    """
    _ensure_keychain()
    service = f"net.boldman.ausearch.trusted-device"
    subprocess.run(
        [
            "security", "add-generic-password",
            "-s", service,
            "-a", peer_device_id,
            "-l", _PEER_CERT_LABEL,
            "-U",
            "-w", certificate_pem.encode("utf-8").hex(),
            *_keychain_arg(),
        ],
        check=True,
    )


def load_peer_certificate(peer_device_id: str) -> str | None:
    """Load a peer device's certificate from the dedicated keychain, or None."""
    _ensure_keychain()
    service = f"net.boldman.ausearch.trusted-device"
    try:
        result = subprocess.run(
            [
                "security", "find-generic-password",
                "-s", service,
                "-a", peer_device_id,
                "-w",
                *_keychain_arg(),
            ],
            capture_output=True,
            check=True,
        )
        return bytes.fromhex(result.stdout.decode("utf-8").strip()).decode("utf-8")
    except subprocess.CalledProcessError:
        return None


def import_peer_certificate(cert: x509.Certificate, peer_device_id: str) -> None:
    """Import a parsed X.509 certificate for a peer device (cf. importPeerCertificate(_:for:))."""
    certificate_pem = cert.public_bytes(
        serialization.Encoding.PEM
    ).decode("utf-8")
    store_peer_certificate(peer_device_id, certificate_pem)


def get_peer_certificate(peer_device_id: str) -> x509.Certificate | None:
    """Load a peer certificate as a parsed x509.Certificate (cf. peerCertificate(for:))."""
    pem = load_peer_certificate(peer_device_id)
    if pem is None:
        return None
    return x509.load_pem_x509_certificate(pem.encode("utf-8"))


def delete_peer_certificate(peer_device_id: str) -> None:
    """Delete a peer device's certificate from the dedicated keychain (cf. deletePeerCertificate(for:))."""
    _ensure_keychain()
    service = f"net.boldman.ausearch.trusted-device"
    try:
        subprocess.run(
            [
                "security", "delete-generic-password",
                "-s", service,
                "-a", peer_device_id,
                *_keychain_arg(),
            ],
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError:
        pass


def _generate_identity(device_id: str) -> DeviceIdentity:
    key = ec.generate_private_key(ec.SECP256R1())
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, device_id),
    ])
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + timedelta(days=365 * _CERT_VALIDITY_YEARS))
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_agreement=True,
                key_encipherment=False,
                data_encipherment=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
                content_commitment=False,
            ),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )
    return DeviceIdentity(
        device_id=device_id,
        certificate_pem=cert.public_bytes(
            serialization.Encoding.PEM
        ).decode("utf-8"),
        private_key=key,
    )
