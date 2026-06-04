#!/usr/bin/env python3
"""
Exact mirror of iOS InstantShareIdentityManager cert generation with diagnostics.
"""

import os
import hashlib
from datetime import datetime, timezone
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import load_pem_public_key, load_der_public_key
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
CN_OID = bytes.fromhex("0603550403")


def encode_spki(raw_x963_point: bytes) -> bytes:
    """Mirrors X509SelfSignedCertificate.encodeSubjectPublicKeyInfo."""
    assert len(raw_x963_point) == 65, f"Expected 65-byte x963 point, got {len(raw_x963_point)}"
    assert raw_x963_point[0] == 0x04, f"x963 point must start with 0x04, got {raw_x963_point[0]:02x}"
    algo_params = encode_asn1_tlv(0x30, EC_PUB_OID + P256_OID)
    pub_key = encode_bit_string(raw_x963_point)
    return encode_asn1_tlv(0x30, algo_params + pub_key)


def encode_algorithm_identifier() -> bytes:
    return encode_asn1_tlv(0x30, ECDSA_SHA256_OID)


def build_distinguished_name(cn: str) -> bytes:
    cn_value = encode_asn1_tlv(0x0C, cn.encode("utf-8"))
    cn_attr = encode_asn1_tlv(0x30, CN_OID + cn_value)
    cn_set = encode_asn1_tlv(0x31, cn_attr)
    return encode_asn1_tlv(0x30, cn_set)


def build_tbs_cert(issuer, subject, spki, not_before, not_after):
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


def raw_ecdsa_sig_to_der(raw: bytes) -> bytes:
    def enc_sig_int(data):
        trimmed = data.lstrip(b"\x00") or b"\x00"
        if trimmed[0] & 0x80:
            trimmed = b"\x00" + trimmed
        return encode_integer(trimmed)
    mid = len(raw) // 2
    return encode_asn1_tlv(0x30, enc_sig_int(raw[:mid]) + enc_sig_int(raw[mid:]))


def build_cert_exact_ios() -> tuple[bytes, ec.EllipticCurvePrivateKey, bytes]:
    """Exact mirror of iOS InstantShareIdentityManager.createAndStoreIdentity cert building."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()

    # iOS uses: cryptoPrivateKey.publicKey.x963Representation (65 bytes: 0x04||x||y)
    pub_numbers = public_key.public_numbers()
    x963_point = b"\x04" + pub_numbers.x.to_bytes(32, "big") + pub_numbers.y.to_bytes(32, "big")
    assert len(x963_point) == 65
    assert x963_point[0] == 0x04

    # iOS: X509SelfSignedCertificate.encodeSubjectPublicKeyInfo(rawPublicKey)
    spki = encode_spki(x963_point)

    # Build TBS cert
    issuer = build_distinguished_name("AuBackup Instant Share")
    now = datetime.now(timezone.utc)
    not_after = datetime(now.year + 10, now.month, now.day, tzinfo=timezone.utc)
    tbs = build_tbs_cert(issuer, issuer, spki, now, not_after)
    sig_algo = encode_algorithm_identifier()

    # iOS: SHA256(tbs) then P256.Signing.PrivateKey.signature(for: digest)
    # In Python: sign() with ec.ECDSA(hashes.SHA256()) does SHA256(data) internally
    signature = private_key.sign(tbs, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(signature)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    der_sig = raw_ecdsa_sig_to_der(raw_sig)
    sig_value = encode_bit_string(der_sig)

    der_cert = encode_asn1_tlv(0x30, tbs + sig_algo + sig_value)

    # Also compute SHA1 of SPKI as iOS does for keychain ApplicationLabel
    spki_sha1 = hashlib.sha1(spki).hexdigest()

    return der_cert, private_key, spki


def main():
    der_cert, priv, spki = build_cert_exact_ios()

    print("=== iOS Certificate Diagnostic ===\n")

    # 1. Parse with pyca/cryptography
    print("1. Parsing DER cert...")
    try:
        cert = x509.load_der_x509_certificate(der_cert)
        print(f"   OK: CN={cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value}")
    except Exception as e:
        print(f"   FAIL: {e}")
        print(f"   DER ({len(der_cert)} bytes): {der_cert.hex()}")
        return 1

    # 2. Verify signature
    print("\n2. Verifying self-signature...")
    try:
        cert.public_key().verify(
            cert.signature,
            cert.tbs_certificate_bytes,
            ec.ECDSA(cert.signature_hash_algorithm),
        )
        print("   OK: signature valid")
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1

    # 3. Extract public key (mirrors SecCertificateCopyKey)
    print("\n3. Extracting public key (SecCertificateCopyKey equivalent)...")
    try:
        embedded_pub = cert.public_key()
        assert isinstance(embedded_pub, ec.EllipticCurvePublicKey)
        print(f"   OK: EC key, curve={embedded_pub.curve.name}")
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1

    # 4. Get SPKI from embedded key and compare
    print("\n4. Comparing SPKI from cert vs our encoded SPKI...")
    cert_spki = embedded_pub.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    print(f"   Our SPKI ({len(spki)} bytes):    {spki.hex()}")
    print(f"   Cert SPKI ({len(cert_spki)} bytes): {cert_spki.hex()}")
    if spki == cert_spki:
        print("   MATCH: Our encoded SPKI == cert's SPKI")
    else:
        print("   MISMATCH!")
        print(f"   SHA1(our spki):   {hashlib.sha1(spki).hexdigest()}")
        print(f"   SHA1(cert spki):  {hashlib.sha1(cert_spki).hexdigest()}")
        return 1

    # 5. PEM export (mirrors publicKeyPEM in iOS)
    print("\n5. PEM export (publicKeyPEM)...")
    try:
        pem = embedded_pub.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("ascii")
        print(f"   OK: {len(pem)} chars, valid PEM")
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1

    # 6. PEM roundtrip
    print("\n6. PEM roundtrip (load_pem_public_key)...")
    try:
        loaded = load_pem_public_key(pem.encode())
        assert isinstance(loaded, ec.EllipticCurvePublicKey)
        print(f"   OK")
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1

    # 7. Compare x963 point
    print("\n7. x963 point verification...")
    pub_numbers = embedded_pub.public_numbers()
    our_x963 = b"\x04" + pub_numbers.x.to_bytes(32, "big") + pub_numbers.y.to_bytes(32, "big")
    print(f"   x963 point: {len(our_x963)} bytes, starts with 0x{our_x963[0]:02x}")
    print(f"   x: {pub_numbers.x.to_bytes(32, 'big').hex()}")
    print(f"   y: {pub_numbers.y.to_bytes(32, 'big').hex()}")

    # 8. Re-encode SPKI and verify
    print("\n8. Re-encoding test (encodeSubjectPublicKeyInfo roundtrip)...")
    spki2 = encode_spki(our_x963)
    pub2 = load_der_public_key(spki2)
    assert isinstance(pub2, ec.EllipticCurvePublicKey)
    pub2_numbers = pub2.public_numbers()
    assert pub2_numbers.x == pub_numbers.x
    assert pub2_numbers.y == pub_numbers.y
    print("   OK: roundtrip x963 -> SPKI -> parse -> same x, y")

    # 9. Apple's SecCertificateCreateWithData equivalent
    # On iOS, the cert is created with SecCertificateCreateWithData(NULL, derData)
    # This is exactly what x509.load_der_x509_certificate does
    print("\n9. Apple SecCertificateCreateWithData equivalent (load_der_x509_certificate)...")
    try:
        cert2 = x509.load_der_x509_certificate(der_cert)
        print(f"   OK: parsed successfully, CN={cert2.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value}")
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1

    print("\n" + "=" * 50)
    print("ALL CHECKS PASSED. Cert DER should work on iOS.")
    print("=" * 50)

    # Print key attrs for keychain debugging
    print(f"\nKeychain ApplicationLabel (SHA1 of SPKI): {hashlib.sha1(spki).hexdigest()}")
    print(f"SPKI size: {len(spki)} bytes")

    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
