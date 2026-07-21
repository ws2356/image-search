import json
import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from fastapi.testclient import TestClient

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    TRANSFER_IMAGE_PATH,
    TRANSFER_TEXT_PATH,
    TRUST_APPLY_PATH,
    TRUST_CONFIRM_PATH,
    TRUST_HANDSHAKE_PATH,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.https_bootstrap import _Deps, _build_app
from dt_image_search.instant_sharing.security import X25519TrustSessionKeyResolver
from dt_image_search.instant_sharing.trust_crypto import AesGcmTrustSessionProtector
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry


def _config(session_id: str | None = None):
    return ConnectionConfig.from_dict(
        {
            "session_id": session_id or str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": ["192.168.1.50"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
    )


class TestTrustSessionLifecycle(unittest.TestCase):
    def test_create_session(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        session = registry.create_session(session_id=session_id, correlation_id=correlation_id)
        self.assertEqual(session.session_id, session_id)
        self.assertIsNone(session.pin_code)
        self.assertFalse(session.is_trusted)

    def test_get_session(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        registry.create_session(session_id=session_id, correlation_id=correlation_id)
        session = registry.get_session(session_id)
        self.assertIsNotNone(session)
        self.assertEqual(session.session_id, session_id)

    def test_get_nonexistent_session_returns_none(self):
        registry = TrustSessionRegistry()
        self.assertIsNone(registry.get_session("nonexistent"))

    def test_require_session_raises_for_missing(self):
        registry = TrustSessionRegistry()
        with self.assertRaises(InstantShareError):
            registry.require_session("nonexistent")

    def test_clear_session(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        registry.create_session(session_id=session_id, correlation_id=correlation_id)
        registry.clear(session_id)
        self.assertIsNone(registry.get_session(session_id))


class TestTrustHandshake(unittest.TestCase):
    def _setup_session_with_key(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        session = registry.create_session(session_id=session_id, correlation_id=correlation_id)

        mobile_key_resolver = X25519TrustSessionKeyResolver()
        mobile_protector = AesGcmTrustSessionProtector(session_key_resolver=mobile_key_resolver)
        mobile_handshake = mobile_key_resolver.handshake_request_payload()
        mobile_dh_public_key = mobile_handshake["mobile_dh_public_key"] if "mobile_dh_public_key" in mobile_handshake else mobile_handshake.get("pc_dh_public_key", "")
        mobile_nonce = mobile_handshake.get("pc_nonce", "")

        pc_handshake = session.handshake_response()
        pc_dh_public_key = pc_handshake["pc_dh_public_key"]
        pc_nonce = pc_handshake["pc_nonce"]

        session.store_mobile_handshake(
            mobile_dh_public_key=mobile_dh_public_key,
            mobile_nonce=mobile_nonce,
        )
        session.establish_session_key()

        return registry, session, session_id, mobile_key_resolver, mobile_protector

    def test_handshake_establishes_session_key(self):
        registry, session, session_id, _, _ = self._setup_session_with_key()
        self.assertTrue(session.is_session_key_established)

    def test_handshake_response_contains_expected_keys(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        session = registry.create_session(session_id=session_id, correlation_id=correlation_id)

        import base64
        mobile_dh_public_key_bytes = os.urandom(32)
        mobile_dh_public_key = base64.urlsafe_b64encode(mobile_dh_public_key_bytes).decode("ascii").rstrip("=")
        mobile_nonce = base64.urlsafe_b64encode(os.urandom(32)).decode("ascii").rstrip("=")

        session.store_mobile_handshake(mobile_dh_public_key=mobile_dh_public_key, mobile_nonce=mobile_nonce)

        response = session.handshake_response()
        self.assertIn("pc_dh_public_key", response)
        self.assertIn("pc_nonce", response)
        self.assertIn("kdf_context", response)

    def test_apply_before_handshake_raises(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        session = registry.create_session(session_id=session_id, correlation_id=correlation_id)
        envelope = {"schema": "dtis.instant-share.trust-envelope.v1", "nonce": "abc", "ciphertext": "abc"}
        with self.assertRaises(InstantShareError) as exc_info:
            session.decrypt_apply_request(envelope)
        self.assertEqual(exc_info.exception.error_code.value, "HANDSHAKE_REQUIRED")

    def test_confirm_before_handshake_raises(self):
        registry = TrustSessionRegistry()
        session_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        session = registry.create_session(session_id=session_id, correlation_id=correlation_id)
        envelope = {"schema": "dtis.instant-share.trust-envelope.v1", "nonce": "abc", "ciphertext": "abc"}
        with self.assertRaises(InstantShareError) as exc_info:
            session.decrypt_confirm_request(envelope)
        self.assertEqual(exc_info.exception.error_code.value, "HANDSHAKE_REQUIRED")

    def test_generate_pin_returns_six_digit_string(self):
        from dt_image_search.instant_sharing.trust_server import _generate_pin_code
        pin = _generate_pin_code()
        self.assertEqual(len(pin), 6)
        self.assertTrue(pin.isdigit())

    def test_mark_trusted_sets_flag(self):
        registry, session, session_id, _, _ = self._setup_session_with_key()
        self.assertFalse(session.is_trusted)
        session.mark_trusted()
        self.assertTrue(session.is_trusted)


class TestEndpointPaths(unittest.TestCase):
    def test_trust_handshake_path(self):
        self.assertEqual(TRUST_HANDSHAKE_PATH, "/api/instant-share/v1/trust/handshake")

    def test_trust_apply_path(self):
        self.assertEqual(TRUST_APPLY_PATH, "/api/instant-share/v1/trust/apply")

    def test_trust_confirm_path(self):
        self.assertEqual(TRUST_CONFIRM_PATH, "/api/instant-share/v1/trust/confirm")

    def test_transfer_text_path(self):
        self.assertEqual(TRANSFER_TEXT_PATH, "/api/instant-share/v1/transfer/text")

    def test_transfer_image_path(self):
        self.assertEqual(TRANSFER_IMAGE_PATH, "/api/instant-share/v1/transfer/image")


class TestFastAPIBootstrap(unittest.TestCase):
    """Smoke tests for the FastAPI app built by `https_bootstrap._build_app`."""

    def _valid_handshake_body(self):
        import base64
        return {
            "mobile_dh_public_key": base64.urlsafe_b64encode(os.urandom(32)).decode("ascii").rstrip("="),
            "mobile_nonce": base64.urlsafe_b64encode(os.urandom(32)).decode("ascii").rstrip("="),
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
            "mobile_port": 1,
            "mobile_ip_list": ["127.0.0.1"],
        }

    def test_handshake_returns_pc_dh_public_key(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(TRUST_HANDSHAKE_PATH, json=self._valid_handshake_body())
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertIn("pc_dh_public_key", body)
        self.assertIn("pc_nonce", body)
        self.assertIn("kdf_context", body)

    def test_handshake_without_deps_returns_503(self):
        app = _build_app(_Deps(trust_session_registry=None))
        with TestClient(app) as client:
            resp = client.post(TRUST_HANDSHAKE_PATH, json=self._valid_handshake_body())
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(resp.json()["error_code"], "SERVICE_UNAVAILABLE")

    def test_malformed_json_returns_422(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(
                TRUST_HANDSHAKE_PATH,
                content=b"not json",
                headers={"Content-Type": "application/json"},
            )
        self.assertEqual(resp.status_code, 422)

    def test_unknown_path_returns_404(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post("/api/instant-share/v1/does-not-exist", json={})
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["error_code"], "NOT_FOUND")

    def test_apply_before_handshake_returns_handshake_required(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(TRUST_APPLY_PATH, json={"schema": "x", "nonce": "y", "ciphertext": "z"})
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error_code"], "HANDSHAKE_REQUIRED")

    def test_transfer_text_without_transfer_handler_returns_503(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(TRANSFER_TEXT_PATH, json={"text_utf8": "hello"})
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(resp.json()["error_code"], "SERVICE_UNAVAILABLE")

    def test_transfer_image_without_transfer_handler_returns_503(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(
                TRANSFER_IMAGE_PATH,
                content=b"\x89PNG\r\n\x1a\n",
                headers={"Content-Type": "image/png", "X-Instant-Share-Filename": "x.png"},
            )
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(resp.json()["error_code"], "SERVICE_UNAVAILABLE")

    def test_confirm_before_handshake_returns_handshake_required(self):
        deps = _Deps(trust_session_registry=TrustSessionRegistry())
        app = _build_app(deps)
        with TestClient(app) as client:
            resp = client.post(TRUST_CONFIRM_PATH, json={"schema": "x", "nonce": "y", "ciphertext": "z"})
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error_code"], "HANDSHAKE_REQUIRED")


if __name__ == "__main__":
    unittest.main()