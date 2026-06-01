import json
import os
import sys
import unittest
import uuid
from datetime import datetime, timedelta

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    DeliveryResult,
    DeliveryTargetResult,
    PayloadClass,
    SessionState,
)
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.http_client import (
    InstantShareHttpClient,
    InstantShareHttpResponse,
    PinnedHttpsRequester,
    RetryPolicy,
)


def _connection_config(
    *,
    payload_class: str = "text",
    target_intent: str = "clipboard_only",
    trust_mode: str = "first_share",
    mobile_ip_list: list[str] | None = None,
):
    return ConnectionConfig.from_dict(
        {
            "session_id": str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": mobile_ip_list or ["192.168.1.5", "fe80::42"],
            "correlation_id": str(uuid.uuid4()),
            "flow_id": "instant_share",
            "payload_class": payload_class,
            "target_intent": target_intent,
            "trust_mode": trust_mode,
        }
    )


class _StubSigner:
    def sign(self, session_id: str) -> tuple[str, str]:
        return (f"signed:{session_id}", "ed25519")


class _StubRequester:
    def __init__(self, *responses):
        self.requests = []
        self._responses = list(responses)

    def __call__(self, request):
        self.requests.append(request)
        response = self._responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def _generate_public_key_and_certificate(common_name: str) -> tuple[str, bytes]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.utcnow() - timedelta(minutes=1))
        .not_valid_after(datetime.utcnow() + timedelta(days=1))
        .sign(private_key, hashes.SHA256())
    )
    public_key_pem = private_key.public_key().public_bytes(
        Encoding.PEM,
        PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")
    certificate_der = certificate.public_bytes(Encoding.DER)
    return public_key_pem, certificate_der


class TestInstantShareHttpClient(unittest.TestCase):
    def test_trust_handshake_builds_unsigned_json_request(self):
        requester = _StubRequester(
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps(
                    {
                        "mobile_dh_public_key": "mobile-dh-pub",
                        "mobile_nonce": "mobile-nonce",
                        "kdf_context": "ctx-001",
                    }
                ).encode("utf-8"),
            )
        )
        client = InstantShareHttpClient(
            connection_config=_connection_config(),
            device_id="pc-001",
            requester=requester,
        )

        payload = client.trust_handshake(
            pc_dh_public_key="desktop-dh-pub",
            pc_nonce="desktop-nonce",
            correlation_id=str(uuid.uuid4()),
        )

        self.assertEqual(payload["mobile_dh_public_key"], "mobile-dh-pub")
        self.assertEqual(len(requester.requests), 1)
        request = requester.requests[0]
        self.assertEqual(request.method, "POST")
        self.assertTrue(request.url.endswith("/api/instant-share/v1/trust/handshake"))
        self.assertNotIn("X-Session-Signature", request.headers)
        body = json.loads(request.body.decode("utf-8"))
        self.assertEqual(body["pc_dh_public_key"], "desktop-dh-pub")
        self.assertEqual(body["payload_class"], "text")
        self.assertEqual(body["target_intent"], "clipboard_only")

    def test_download_text_uses_signed_headers_and_ip_fallback(self):
        requester = _StubRequester(
            OSError("primary ip unreachable"),
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps({"state": "delivering", "text_utf8": "hello from ios"}).encode("utf-8"),
            ),
        )
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="trusted_direct"),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
            pinned_mobile_public_key_pem="mobile-public-key-pem",
        )

        payload = client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(payload.text_utf8, "hello from ios")
        self.assertEqual(len(requester.requests), 2)
        self.assertEqual(requester.requests[0].url.split("/api/")[0], "https://192.168.1.5:8443")
        self.assertEqual(requester.requests[1].url.split("/api/")[0], "https://[fe80::42]:8443")
        self.assertIn("X-Session-Signature", requester.requests[1].headers)
        self.assertEqual(requester.requests[1].headers["X-Session-Signature-Alg"], "ed25519")
        self.assertTrue(requester.requests[1].requires_tls_pin)
        self.assertEqual(requester.requests[1].pinned_mobile_public_key_pem, "mobile-public-key-pem")

    def test_download_image_parses_response_headers(self):
        requester = _StubRequester(
            InstantShareHttpResponse(
                status_code=200,
                headers={
                    "Content-Type": "image/png",
                    "X-Instant-Share-Filename": "shared.png",
                    "X-Instant-Share-Manifest": json.dumps({"width": 32, "height": 32}),
                },
                body=b"png-binary",
            )
        )
        client = InstantShareHttpClient(
            connection_config=_connection_config(payload_class="image", target_intent="clipboard_or_file", trust_mode="trusted_direct"),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
            pinned_mobile_public_key_pem="mobile-public-key-pem",
        )

        payload = client.download_image_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(payload.metadata.payload_class, PayloadClass.IMAGE)
        self.assertEqual(payload.filename, "shared.png")
        self.assertEqual(payload.content_type, "image/png")
        self.assertEqual(payload.image_bytes, b"png-binary")
        self.assertEqual(payload.manifest["width"], 32)

    def test_report_delivery_result_posts_terminal_schema(self):
        requester = _StubRequester(
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps({"ack": True}).encode("utf-8"),
            )
        )
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="trusted_direct"),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
            pinned_mobile_public_key_pem="mobile-public-key-pem",
        )

        ack_payload = client.report_delivery_result(
            correlation_id=str(uuid.uuid4()),
            result=DeliveryResult(
                state=SessionState.DONE,
                target_result=DeliveryTargetResult(clipboard_written=True),
            ),
        )

        self.assertTrue(ack_payload["ack"])
        body = json.loads(requester.requests[0].body.decode("utf-8"))
        self.assertEqual(body["state"], "done")
        self.assertEqual(body["target_result"]["clipboard_written"], True)

    def test_transfer_requests_require_pinned_mobile_public_key(self):
        requester = _StubRequester()
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="trusted_direct"),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
        )

        with self.assertRaises(InstantShareError) as exc_info:
            client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(exc_info.exception.error_code.value, "TRUSTED_KEY_NOT_FOUND")
        self.assertEqual(requester.requests, [])

    def test_trust_confirm_stores_mobile_public_key_for_subsequent_transfer_requests(self):
        requester = _StubRequester(
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps(
                    {
                        "mobile_public_key_pem": "mobile-public-key-pem-from-confirm",
                        "trust_status": "trusted",
                    }
                ).encode("utf-8"),
            ),
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps({"state": "delivering", "text_utf8": "hello from ios"}).encode("utf-8"),
            ),
        )
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="first_share"),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
        )

        trust_payload = client.trust_confirm(
            pc_public_key_pem="desktop-public-key",
            correlation_id=str(uuid.uuid4()),
        )
        downloaded_payload = client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(trust_payload["trust_status"], "trusted")
        self.assertEqual(downloaded_payload.text_utf8, "hello from ios")
        self.assertEqual(client.pinned_mobile_public_key_pem, "mobile-public-key-pem-from-confirm")
        self.assertEqual(requester.requests[1].pinned_mobile_public_key_pem, "mobile-public-key-pem-from-confirm")
        self.assertTrue(requester.requests[1].requires_tls_pin)

    def test_verify_peer_public_key_pin_accepts_matching_public_key(self):
        pinned_public_key_pem, certificate_der = _generate_public_key_and_certificate("mobile.local")

        PinnedHttpsRequester.verify_peer_public_key_pin(
            peer_certificate_der=certificate_der,
            pinned_mobile_public_key_pem=pinned_public_key_pem,
            url="https://127.0.0.1:8443/api/instant-share/v1/payload/text",
        )

    def test_verify_peer_public_key_pin_rejects_mismatched_public_key(self):
        _, certificate_der = _generate_public_key_and_certificate("mobile.local")
        mismatched_public_key_pem, _ = _generate_public_key_and_certificate("other.local")

        with self.assertRaises(InstantShareError) as exc_info:
            PinnedHttpsRequester.verify_peer_public_key_pin(
                peer_certificate_der=certificate_der,
                pinned_mobile_public_key_pem=mismatched_public_key_pem,
                url="https://127.0.0.1:8443/api/instant-share/v1/payload/text",
            )

        self.assertEqual(exc_info.exception.error_code.value, "TLS_PIN_VALIDATION_FAILED")

    def test_download_text_retries_transient_errors_with_backoff(self):
        requester = _StubRequester(
            OSError("temporary network issue"),
            InstantShareHttpResponse(
                status_code=200,
                headers={"Content-Type": "application/json"},
                body=json.dumps({"state": "delivering", "text_utf8": "retried payload"}).encode("utf-8"),
            ),
        )
        sleep_calls = []
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="trusted_direct", mobile_ip_list=["192.168.1.5"]),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
            pinned_mobile_public_key_pem="mobile-public-key-pem",
            retry_policy=RetryPolicy(max_attempts=2, backoff_seconds=(0.25,)),
            sleep_func=sleep_calls.append,
        )

        payload = client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(payload.text_utf8, "retried payload")
        self.assertEqual(sleep_calls, [0.25])
        self.assertEqual(len(requester.requests), 2)

    def test_download_text_raises_transfer_timeout_after_retry_exhaustion(self):
        requester = _StubRequester(
            OSError("temporary network issue"),
            OSError("temporary network issue"),
            OSError("temporary network issue"),
        )
        sleep_calls = []
        client = InstantShareHttpClient(
            connection_config=_connection_config(trust_mode="trusted_direct", mobile_ip_list=["192.168.1.5"]),
            device_id="pc-001",
            requester=requester,
            session_signer=_StubSigner(),
            pinned_mobile_public_key_pem="mobile-public-key-pem",
            retry_policy=RetryPolicy(max_attempts=3, backoff_seconds=(0.1, 0.2)),
            sleep_func=sleep_calls.append,
        )

        with self.assertRaises(InstantShareError) as exc_info:
            client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(exc_info.exception.error_code.value, "TRANSFER_TIMEOUT")
        self.assertEqual(sleep_calls, [0.1, 0.2])


if __name__ == "__main__":
    unittest.main()