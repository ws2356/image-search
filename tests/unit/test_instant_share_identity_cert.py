"""Tests for iOS X509SelfSignedCertificate / InstantShareIdentityManager cert generation.

Validates that the DER certificate construction logic is correct,
independent of iOS keychain import.
"""

import hashlib
import os
from datetime import datetime, timezone

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import load_pem_public_key
from cryptography.x509.oid import NameOID


def encode_asn1_tlv(tag: int, value: bytes) -> bytes:
    result = bytearray([tag])
    length = len(value)
    if length < 128:
        result.append(length)
    else:
        len_bytes = bytearray()
        rem = length
        while rem > 0:
            len_bytes.insert(0, rem & 0xFF)
            rem >>= 8
        result.append(0x80 | len(len_bytes))
        result.extend(len_bytes)
    result.extend(value)
    return bytes(result)


def encode_integer(value: bytes) -> bytes:
    v = bytearray(value)
    if v and (v[0] & 0x80):
        v.insert(0, 0)
    return encode_asn1_tlv(0x02, bytes(v))


def encode_bit_string(value: bytes) -> bytes:
    return encode_asn1_tlv(0x03, b"\x00" + value)


def encode_time(dt: datetime) -> bytes:
    s = dt.strftime("%y%m%d%H%M%SZ")
    return encode_asn1_tlv(0x17, s.encode("ascii"))


EC_PUB_OID = bytes.fromhex("06072A8648CE3D0201")
P256_OID = bytes.fromhex("06082A8648CE3D030107")
ECDSA_SHA256_OID = bytes.fromhex("06082A8648CE3D040302")


def encode_spki(raw_public_key: bytes) -> bytes:
    algo_params = encode_asn1_tlv(0x30, EC_PUB_OID + P256_OID)
    pub_key = encode_bit_string(raw_public_key)
    return encode_asn1_tlv(0x30, algo_params + pub_key)


def encode_algorithm_identifier() -> bytes:
    return encode_asn1_tlv(0x30, ECDSA_SHA256_OID)


def build_distinguished_name(cn: str) -> bytes:
    cn_oid = bytes.fromhex("0603550403")
    cn_value = encode_asn1_tlv(0x0C, cn.encode("utf-8"))
    cn_attr = encode_asn1_tlv(0x30, cn_oid + cn_value)
    cn_set = encode_asn1_tlv(0x31, cn_attr)
    return encode_asn1_tlv(0x30, cn_set)


def build_tbs_certificate(
    issuer: bytes,
    subject: bytes,
    spki: bytes,
    not_before: datetime,
    not_after: datetime,
) -> bytes:
    serial = os.urandom(16)
    inner = bytearray()
    inner += encode_integer(serial)
    inner += encode_algorithm_identifier()
    inner += issuer
    validity = encode_time(not_before) + encode_time(not_after)
    inner += encode_asn1_tlv(0x30, validity)
    inner += subject
    inner += spki
    return encode_asn1_tlv(0x30, bytes(inner))


def encode_ecdsa_sig_integer(data: bytes) -> bytes:
    trimmed = data.lstrip(b"\x00") or b"\x00"
    if trimmed[0] & 0x80:
        trimmed = b"\x00" + trimmed
    return encode_integer(trimmed)


def raw_ecdsa_sig_to_der(raw: bytes) -> bytes:
    mid = len(raw) // 2
    r_enc = encode_ecdsa_sig_integer(raw[:mid])
    s_enc = encode_ecdsa_sig_integer(raw[mid:])
    return encode_asn1_tlv(0x30, r_enc + s_enc)


def build_self_signed_cert_der() -> tuple[bytes, ec.EllipticCurvePrivateKey]:
    """Mirrors the iOS InstantShareIdentityManager cert generation."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()

    pub_numbers = public_key.public_numbers()
    raw_pub = b"\x04" + pub_numbers.x.to_bytes(32, "big") + pub_numbers.y.to_bytes(32, "big")

    issuer = build_distinguished_name("AuBackup Instant Share")
    now = datetime.now(timezone.utc)
    not_after = datetime(now.year + 10, now.month, now.day, tzinfo=timezone.utc)

    spki = encode_spki(raw_pub)
    tbs = build_tbs_certificate(issuer, issuer, spki, now, not_after)
    sig_algo = encode_algorithm_identifier()

    signature = private_key.sign(tbs, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(signature)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    der_sig = raw_ecdsa_sig_to_der(raw_sig)
    sig_value = encode_bit_string(der_sig)

    der_cert = encode_asn1_tlv(0x30, tbs + sig_algo + sig_value)
    return der_cert, private_key


class TestIdentityCertGeneration:
    """Tests mirroring the iOS X509SelfSignedCertificate + InstantShareIdentityManager logic."""

    def test_cert_parses(self):
        der, priv = build_self_signed_cert_der()
        cert = x509.load_der_x509_certificate(der)
        cn = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
        assert cn == "AuBackup Instant Share"

    def test_signature_validates(self):
        der, priv = build_self_signed_cert_der()
        cert = x509.load_der_x509_certificate(der)
        cert.public_key().verify(
            cert.signature,
            cert.tbs_certificate_bytes,
            ec.ECDSA(cert.signature_hash_algorithm),
        )

    def test_spki_pem_output(self):
        der, priv = build_self_signed_cert_der()
        cert = x509.load_der_x509_certificate(der)
        pem = cert.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("ascii")
        assert pem.startswith("-----BEGIN PUBLIC KEY-----")
        assert pem.endswith("-----END PUBLIC KEY-----\n")

    def test_spki_pem_roundtrip(self):
        der, priv = build_self_signed_cert_der()
        cert = x509.load_der_x509_certificate(der)
        pem = cert.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("ascii")
        loaded = load_pem_public_key(pem.encode())
        assert isinstance(loaded, ec.EllipticCurvePublicKey)

    def test_multiple_certs_idempotent(self):
        """Generating multiple certs should always produce valid certs."""
        for _ in range(5):
            der, priv = build_self_signed_cert_der()
            cert = x509.load_der_x509_certificate(der)
            cert.public_key().verify(
                cert.signature,
                cert.tbs_certificate_bytes,
                ec.ECDSA(cert.signature_hash_algorithm),
            )


class TestPrehashedSigning:
    """
    Verify pre-hashed ECDSA signature (SHA-256 digest -> ECDSA sign)
    matches the iOS SecKeyCreateSignature(.ecdsaSignatureDigestX962SHA256) behavior.
    """

    def test_cert_with_prehashed_signing(self):
        """Build a cert using pre-hashed signing (matching iOS SecKeyCreateSignature approach)."""
        from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
        import hashlib

        private_key = ec.generate_private_key(ec.SECP256R1())
        public_key = private_key.public_key()
        pub_numbers = public_key.public_numbers()
        raw_pub = b"\x04" + pub_numbers.x.to_bytes(32, "big") + pub_numbers.y.to_bytes(32, "big")

        issuer = build_distinguished_name("AuBackup Instant Share")
        now = datetime.now(timezone.utc)
        not_after = datetime(now.year + 10, now.month, now.day, tzinfo=timezone.utc)
        spki = encode_spki(raw_pub)
        tbs = build_tbs_certificate(issuer, issuer, spki, now, not_after)
        sig_algo = encode_algorithm_identifier()

        # iOS approach: SHA256(tbs) then sign with .ecdsaSignatureDigestX962SHA256
        digest = hashlib.sha256(tbs).digest()
        signature = private_key.sign(digest, ec.ECDSA(Prehashed(hashes.SHA256())))
        r, s = decode_dss_signature(signature)
        raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        der_sig = raw_ecdsa_sig_to_der(raw_sig)
        sig_value = encode_bit_string(der_sig)
        der_cert = encode_asn1_tlv(0x30, tbs + sig_algo + sig_value)

        cert = x509.load_der_x509_certificate(der_cert)
        assert cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value == "AuBackup Instant Share"
        cert.public_key().verify(
            cert.signature, cert.tbs_certificate_bytes,
            ec.ECDSA(cert.signature_hash_algorithm),
        )
