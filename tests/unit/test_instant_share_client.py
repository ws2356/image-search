import json
import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    DeliveryResult,
    DeliveryTargetResult,
    PayloadClass,
    SessionState,
)
from dt_image_search.instant_sharing.http_client import (
    InstantShareHttpClient,
    InstantShareHttpResponse,
)


def _connection_config(*, payload_class: str = "text", target_intent: str = "clipboard_only", trust_mode: str = "first_share"):
    return ConnectionConfig.from_dict(
        {
            "session_id": str(uuid.uuid4()),
            "mobile_port": 8443,
            "mobile_ip_list": ["192.168.1.5", "fe80::42"],
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
        )

        payload = client.download_text_payload(correlation_id=str(uuid.uuid4()))

        self.assertEqual(payload.text_utf8, "hello from ios")
        self.assertEqual(len(requester.requests), 2)
        self.assertEqual(requester.requests[0].url.split("/api/")[0], "https://192.168.1.5:8443")
        self.assertEqual(requester.requests[1].url.split("/api/")[0], "https://[fe80::42]:8443")
        self.assertIn("X-Session-Signature", requester.requests[1].headers)
        self.assertEqual(requester.requests[1].headers["X-Session-Signature-Alg"], "ed25519")

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


if __name__ == "__main__":
    unittest.main()