import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from dt_image_search.instant_sharing.sender_validation import SenderIdentity
from dt_image_search.instant_sharing.security import PersistentEd25519SessionSigner
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.contracts import ErrorCode


class SenderIdentityTests(unittest.TestCase):
    def test_from_config_dir_creates_key_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config_dir = Path(tmp) / "identity"
            identity = SenderIdentity.from_config_dir(config_dir, device_id="test-device")
            self.assertTrue((config_dir / "instant_share_ed25519.pem").exists())
            self.assertEqual(identity.device_id, "test-device")

    def test_sign_session_id_returns_signature_and_algorithm(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            signature, algorithm = identity.sign_session_id("abc-123")
            self.assertEqual(algorithm, "ed25519")
            self.assertTrue(len(signature) > 0)

    def test_sign_session_id_rejects_empty_session_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            with self.assertRaises(InstantShareError) as ctx:
                identity.sign_session_id("")
            self.assertEqual(ctx.exception.error_code, ErrorCode.SESSION_SIGNATURE_INVALID)

    def test_public_key_pem_is_valid_pem(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            pem = identity.public_key_pem()
            self.assertTrue(pem.startswith("-----BEGIN PUBLIC KEY-----"))
            self.assertTrue(pem.strip().endswith("-----END PUBLIC KEY-----"))

    def test_device_signature_advertisement_has_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="my-mac")
            ad = identity.device_signature_advertisement()
            self.assertEqual(ad.signature_key_id, "my-mac")
            self.assertTrue(len(ad.signature) > 0)
            self.assertGreater(ad.timestamp_ms, 0)

    def test_reuses_existing_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity1 = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            pem1 = identity1.public_key_pem()
            identity2 = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            pem2 = identity2.public_key_pem()
            self.assertEqual(pem1, pem2)

    def test_session_signer_is_persistent_ed25519(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            self.assertIsInstance(identity.session_signer, PersistentEd25519SessionSigner)

    def test_rejects_empty_device_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                SenderIdentity.from_config_dir(Path(tmp), device_id="")


class SessionSignatureHeaderTests(unittest.TestCase):
    def test_signer_produces_consistent_signatures(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            session_id = "550e8400-e29b-41d4-a716-446655440000"
            sig1, alg1 = identity.sign_session_id(session_id)
            sig2, alg2 = identity.sign_session_id(session_id)
            self.assertEqual(alg1, "ed25519")
            self.assertEqual(alg2, "ed25519")
            self.assertEqual(sig1, sig2)

    def test_different_sessions_produce_different_signatures(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            identity = SenderIdentity.from_config_dir(Path(tmp), device_id="dev")
            sig1, _ = identity.sign_session_id("550e8400-e29b-41d4-a716-446655440000")
            sig2, _ = identity.sign_session_id("660e8400-e29b-41d4-a716-446655440000")
            self.assertNotEqual(sig1, sig2)


if __name__ == "__main__":
    unittest.main()
