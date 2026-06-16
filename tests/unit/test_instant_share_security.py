import base64
import os
import sys
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, load_pem_public_key

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.security import (
    PersistentEd25519SessionSigner,
    X25519TrustSessionKeyResolver,
)


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


class TestX25519TrustSessionKeyResolver(unittest.TestCase):
    def test_derives_same_session_key_as_mobile_peer(self):
        resolver = X25519TrustSessionKeyResolver()
        handshake_request = resolver.handshake_request_payload()

        mobile_private_key = x25519.X25519PrivateKey.generate()
        mobile_public_key = mobile_private_key.public_key().public_bytes(
            Encoding.Raw,
            PublicFormat.Raw,
        )
        mobile_nonce = os.urandom(32)
        kdf_context = os.urandom(16)
        handshake_response = {
            "mobile_dh_public_key": base64.urlsafe_b64encode(mobile_public_key).decode("ascii").rstrip("="),
            "mobile_nonce": base64.urlsafe_b64encode(mobile_nonce).decode("ascii").rstrip("="),
            "kdf_context": base64.urlsafe_b64encode(kdf_context).decode("ascii").rstrip("="),
        }

        derived_session_key = resolver(
            handshake_request=handshake_request,
            handshake_response=handshake_response,
        )

        peer_public_key = x25519.X25519PublicKey.from_public_bytes(
            _base64url_decode(handshake_request["pc_dh_public_key"])
        )
        shared_secret = mobile_private_key.exchange(peer_public_key)
        expected_session_key = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=_base64url_decode(handshake_request["pc_nonce"]) + mobile_nonce,
            info=b"dtis.instant-share.trust-session.v1" + kdf_context,
        ).derive(shared_secret)

        self.assertEqual(derived_session_key, expected_session_key)


class TestPersistentEd25519SessionSigner(unittest.TestCase):
    def test_reuses_persisted_key_and_signs_session_ids(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            key_path = Path(temp_dir) / "instant-share-ed25519.pem"
            signer = PersistentEd25519SessionSigner(key_path)

            signature, algorithm = signer.sign("session-123")
            public_key_pem = signer.public_key_pem()

            reloaded_signer = PersistentEd25519SessionSigner(key_path)
            reloaded_signature, reloaded_algorithm = reloaded_signer.sign("session-123")

            self.assertEqual(algorithm, "ed25519")
            self.assertEqual(reloaded_algorithm, "ed25519")
            self.assertEqual(public_key_pem, reloaded_signer.public_key_pem())
            self.assertEqual(signature, reloaded_signature)

            public_key = load_pem_public_key(public_key_pem.encode("utf-8"))
            public_key.verify(_base64url_decode(signature), b"session-123")


if __name__ == "__main__":
    unittest.main()