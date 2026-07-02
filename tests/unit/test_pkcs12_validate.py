#!/usr/bin/env python3
"""Validate PKCS#12 DER construction matching iOS buildPKCS12()."""
import hashlib
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption
from cryptography.x509.oid import NameOID
from cryptography import x509
from datetime import datetime, timezone
import os

# Mirror iOS ASN.1 helpers
def tlv(tag, value):
    result = bytearray([tag])
    l = len(value)
    if l < 128:
        result.append(l)
    else:
        lb = bytearray()
        rem = l
        while rem:
            lb.insert(0, rem & 0xFF)
            rem >>= 8
        result.append(0x80 | len(lb))
        result.extend(lb)
    result.extend(value)
    return bytes(result)

def tlv30(value):
    return tlv(0x30, value)

def tlv02(value):
    return tlv(0x02, value)

def tlv04(value):
    return tlv(0x04, value)

def tlvA0(value):
    return tlv(0xA0, value)

def tlv03(value):
    return tlv(0x03, value)

# OIDs (matching iOS)
PKCS7_DATA_OID = bytes.fromhex("06092A864886F70D010701")
PKCS8_KEY_BAG_OID = bytes.fromhex("060A2A864886F70D010C0A0102")  # pkcs8KeyBag (unencrypted)
CERT_BAG_OID = bytes.fromhex("060A2A864886F70D010C0A0103")       # certBag
X509_CERT_OID = bytes.fromhex("06092A864886F70D0109162201")       # x509Certificate
EC_PUB_OID = bytes.fromhex("06072A8648CE3D0201")
P256_OID = bytes.fromhex("06082A8648CE3D030107")
ECDSA_SHA256_OID = bytes.fromhex("06082A8648CE3D040302")
CN_OID = bytes.fromhex("0603550403")


def build_spki(raw_pub):
    algo = tlv30(EC_PUB_OID + P256_OID)
    pub = tlv03(b'\x00' + raw_pub)
    return tlv30(algo + pub)


def build_dn(cn):
    cn_val = tlv(0x0C, cn.encode())
    cn_attr = tlv30(CN_OID + cn_val)
    cn_set = tlv(0x31, cn_attr)
    return tlv30(cn_set)


def build_tbs(issuer, subject, spki, nb, na):
    serial = os.urandom(16)
    inner = bytearray()
    inner += tlv02(serial)
    inner += tlv30(ECDSA_SHA256_OID)
    inner += issuer
    inner += tlv30(tlv(0x17, nb.strftime("%y%m%d%H%M%SZ").encode()) +
                    tlv(0x17, na.strftime("%y%m%d%H%M%SZ").encode()))
    inner += subject
    inner += spki
    return tlv30(bytes(inner))


def raw_to_der_sig(raw):
    mid = len(raw) // 2
    def enc(b):
        t = b.lstrip(b'\x00') or b'\x00'
        if t[0] & 0x80:
            t = b'\x00' + t
        return tlv02(t)
    return tlv30(enc(raw[:mid]) + enc(raw[mid:]))


def build_cert_der():
    priv = ec.generate_private_key(ec.SECP256R1())
    pub = priv.public_key()
    pub_nums = pub.public_numbers()
    raw_pub = b'\x04' + pub_nums.x.to_bytes(32, 'big') + pub_nums.y.to_bytes(32, 'big')

    dn = build_dn("AuBackup Instant Share")
    now = datetime.now(timezone.utc)
    na = datetime(now.year + 10, now.month, now.day, tzinfo=timezone.utc)
    spki = build_spki(raw_pub)
    tbs = build_tbs(dn, dn, spki, now, na)
    sig_algo = tlv30(ECDSA_SHA256_OID)

    digest = hashlib.sha256(tbs).digest()
    sig = priv.sign(tbs, ec.ECDSA(hashes.SHA256()))
    r, s = (int.from_bytes(sig[:32], 'big'), int.from_bytes(sig[32:], 'big'))
    # Wait, decode_dss_signature is needed
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    r, s = decode_dss_signature(sig)
    raw_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    der_sig = raw_to_der_sig(raw_sig)
    sig_value = tlv03(b'\x00' + der_sig)

    der_cert = tlv30(tbs + sig_algo + sig_value)
    return der_cert, priv, raw_pub


def build_pkcs8(x963, raw_pub):
    """Mirrors iOS encodePKCS8PrivateKey()."""
    ec_ver = tlv02(b'\x01')
    ec_priv = tlv04(x963)
    ec_pub = tlv(0xA1, tlv03(b'\x00' + raw_pub))
    ec_inner = ec_ver + ec_priv + ec_pub
    ec_key_seq = tlv30(ec_inner)

    ver = tlv02(b'\x00')
    algo = tlv30(EC_PUB_OID + P256_OID)
    wrapped = tlv04(ec_key_seq)
    return tlv30(ver + algo + wrapped)


def build_pkcs12(pkcs8, cert_der):
    """Mirrors iOS buildPKCS12()."""
    # SafeBag for key
    key_val = tlvA0(tlv04(pkcs8))
    key_bag = tlv30(PKCS8_KEY_BAG_OID + key_val)

    # SafeBag for cert
    cert_inner = X509_CERT_OID + tlvA0(tlv04(cert_der))
    cert_bag = tlv30(CERT_BAG_OID + cert_inner)

    # SafeContents
    safe_contents = tlv30(key_bag + cert_bag)

    # AuthenticatedSafe: one ContentInfo(pkcs7-data)
    safe_content = PKCS7_DATA_OID + tlvA0(tlv04(safe_contents))
    auth_safe = tlv30(safe_content)

    # PFX
    version = tlv02(b'\x03')
    auth_wrapped = PKCS7_DATA_OID + tlvA0(tlv04(auth_safe))
    inner = version + tlv30(auth_wrapped)
    return tlv30(inner)


def main():
    cert_der, priv, raw_pub = build_cert_der()
    print(f"Cert DER: {len(cert_der)} bytes")
    print(f"Cert parse: {x509.load_der_x509_certificate(cert_der).subject}")

    x963 = priv.private_numbers().private_value.to_bytes(32, 'big')
    pkcs8 = build_pkcs8(x963, raw_pub)
    print(f"PKCS#8: {len(pkcs8)} bytes")

    p12 = build_pkcs12(pkcs8, cert_der)
    print(f"PKCS#12: {len(p12)} bytes")
    print(f"PKCS#12 hex (first 60): {p12[:60].hex()}")

    # Try to parse with cryptography
    try:
        key, cert, cas = pkcs12.load_key_and_certificates(p12, b"")
        print(f"PKCS#12 parsed OK! key={key}, cert CN={cert.subject}")
        print("SUCCESS: PKCS#12 structure is valid")
    except Exception as e:
        print(f"PKCS#12 parse FAILED: {e}")
        # dump structure
        print(f"Full DER ({len(p12)} bytes): {p12.hex()}")

    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
