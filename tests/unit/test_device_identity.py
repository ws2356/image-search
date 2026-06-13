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


if __name__ == "__main__":
    unittest.main()
