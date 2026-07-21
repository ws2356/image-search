import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from dt_image_search.identity.device_identity import (
    delete_peer_certificate,
    extract_device_id,
    extract_device_name,
    generate_identity,
    get_peer_certificate,
    import_peer_certificate,
    load_peer_certificate,
    store_peer_certificate,
)


def _make_test_cert(common_name: str) -> tuple[ec.EllipticCurvePrivateKey, x509.Certificate]:
    key = ec.generate_private_key(ec.SECP256R1())
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ])
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    return key, cert


class TestPeerCertificateManagement(unittest.TestCase):
    peer_1 = "test-peer-device-1"
    peer_2 = "test-peer-device-2"
    nonexistent = "non-existent-peer"

    def tearDown(self):
        for pid in (self.peer_1, self.peer_2):
            try:
                delete_peer_certificate(pid)
            except Exception:
                pass

    def test_import_peer_certificate_round_trip(self):
        _, cert = _make_test_cert(self.peer_1)
        import_peer_certificate(cert, self.peer_1)
        retrieved = get_peer_certificate(self.peer_1)
        self.assertIsNotNone(retrieved)
        self.assertEqual(
            cert.public_bytes(serialization.Encoding.DER),
            retrieved.public_bytes(serialization.Encoding.DER),
        )

    def test_store_peer_certificate_pem_round_trip(self):
        _, cert = _make_test_cert(self.peer_1)
        pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
        store_peer_certificate(self.peer_1, pem)
        loaded = load_peer_certificate(self.peer_1)
        self.assertIsNotNone(loaded)
        self.assertEqual(pem.strip(), loaded.strip())

    def test_store_peer_certificate_overwrites_existing(self):
        _, cert = _make_test_cert(self.peer_1)
        pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
        store_peer_certificate(self.peer_1, pem)
        store_peer_certificate(self.peer_1, pem)
        loaded = load_peer_certificate(self.peer_1)
        self.assertEqual(pem.strip(), loaded.strip())

    def test_get_peer_certificate_not_found_returns_none(self):
        self.assertIsNone(get_peer_certificate(self.nonexistent))

    def test_load_peer_certificate_not_found_returns_none(self):
        self.assertIsNone(load_peer_certificate(self.nonexistent))

    def test_delete_peer_certificate_removes_it(self):
        _, cert = _make_test_cert(self.peer_1)
        import_peer_certificate(cert, self.peer_1)
        self.assertIsNotNone(get_peer_certificate(self.peer_1))
        delete_peer_certificate(self.peer_1)
        self.assertIsNone(get_peer_certificate(self.peer_1))

    def test_delete_peer_certificate_nonexistent_does_not_raise(self):
        try:
            delete_peer_certificate(self.nonexistent)
        except Exception:
            self.fail("delete_peer_certificate raised on nonexistent peer")

    def test_peer_certificates_isolated_by_id(self):
        _, cert1 = _make_test_cert(self.peer_1)
        _, cert2 = _make_test_cert(self.peer_2)
        import_peer_certificate(cert1, self.peer_1)
        import_peer_certificate(cert2, self.peer_2)
        retrieved1 = get_peer_certificate(self.peer_1)
        retrieved2 = get_peer_certificate(self.peer_2)
        self.assertIsNotNone(retrieved1)
        self.assertIsNotNone(retrieved2)
        self.assertNotEqual(
            retrieved1.public_bytes(serialization.Encoding.DER),
            retrieved2.public_bytes(serialization.Encoding.DER),
        )


class TestCertIdentityV3(unittest.TestCase):
    """Tests for certificate identity v3: device name in CN, UUID in extension."""

    def test_generate_identity_sets_cn_to_desktop_name(self):
        identity = generate_identity(device_id="test-uuid-001", desktop_name="My Test Mac")
        cert = x509.load_pem_x509_certificate(identity.certificate_pem.encode("utf-8"))
        self.assertEqual(extract_device_name(cert), "My Test Mac")

    def test_generate_identity_includes_device_id_in_extension(self):
        identity = generate_identity(device_id="550e8400-e29b-41d4-a716-446655440000", desktop_name="My Mac")
        cert = x509.load_pem_x509_certificate(identity.certificate_pem.encode("utf-8"))
        self.assertEqual(
            extract_device_id(cert),
            "550e8400-e29b-41d4-a716-446655440000",
        )

    def test_generate_identity_cn_is_not_device_id(self):
        """CN should be the name, NOT the device UUID."""
        identity = generate_identity(device_id="should-not-appear", desktop_name="Visible Name")
        cert = x509.load_pem_x509_certificate(identity.certificate_pem.encode("utf-8"))
        cn_value = extract_device_name(cert)
        self.assertEqual(cn_value, "Visible Name")
        self.assertNotIn("should-not-appear", cn_value)

    def test_extract_device_name_and_id_round_trip(self):
        identity = generate_identity(device_id="abc-123-xyz", desktop_name="John's iPhone")
        cert = x509.load_pem_x509_certificate(identity.certificate_pem.encode("utf-8"))
        self.assertEqual(extract_device_name(cert), "John's iPhone")
        self.assertEqual(extract_device_id(cert), "abc-123-xyz")

    def test_generate_identity_produces_valid_device_identity(self):
        identity = generate_identity(device_id="dev-42", desktop_name="TestMac")
        self.assertEqual(identity.device_id, "dev-42")
        self.assertIn("-----BEGIN CERTIFICATE-----", identity.certificate_pem)
        self.assertIsNotNone(identity.private_key)

    def test_extract_device_id_decodes_asn1_utf8string_extension(self):
        """The device UUID is stored as an ASN.1 DER UTF8String in the custom extension."""
        from cryptography.hazmat.primitives.asymmetric import ec
        from dt_image_search.identity.device_identity import _DEVICE_ID_OID

        private_key = ec.generate_private_key(ec.SECP256R1())
        subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "iPhone")])
        device_uuid = "4506ab98-cfb6-42c1-a937-56c3b88ba8bf"
        # DER-encoded UTF8String: tag 0x0c, length 0x24 (36), then UTF-8 bytes
        extension_value = bytes([0x0C, 36]) + device_uuid.encode("utf-8")
        ext = x509.UnrecognizedExtension(_DEVICE_ID_OID, extension_value)
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(private_key.public_key())
            .serial_number(1)
            .not_valid_before(datetime.utcnow() - timedelta(days=1))
            .not_valid_after(datetime.utcnow() + timedelta(days=365))
            .add_extension(ext, critical=False)
            .sign(private_key, hashes.SHA256())
        )
        self.assertEqual(extract_device_id(cert), device_uuid)

    def test_extract_device_id_rejects_raw_bytes_extension(self):
        """Raw UTF-8 bytes in the extension are no longer accepted."""
        from cryptography.hazmat.primitives.asymmetric import ec
        from dt_image_search.identity.device_identity import _DEVICE_ID_OID

        private_key = ec.generate_private_key(ec.SECP256R1())
        subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "iPhone")])
        ext = x509.UnrecognizedExtension(_DEVICE_ID_OID, b"4506ab98-cfb6-42c1-a937-56c3b88ba8bf")
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(private_key.public_key())
            .serial_number(1)
            .not_valid_before(datetime.utcnow() - timedelta(days=1))
            .not_valid_after(datetime.utcnow() + timedelta(days=365))
            .add_extension(ext, critical=False)
            .sign(private_key, hashes.SHA256())
        )
        self.assertIsNone(extract_device_id(cert))


if __name__ == "__main__":
    unittest.main()
