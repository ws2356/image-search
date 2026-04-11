import errno
import http.client
import json
import os
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from urllib.parse import urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import (
    MobilePairingService,
    PairingResultState,
    _is_ignorable_socket_disconnect,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64
from dt_image_search.model.dts_db import create_db_conn


class TestMobilePairingService(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"pairing-tests-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{self._ctx.subfolder}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

        self._pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            advertised_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(self._pairing_service.shutdown)

    def test_handle_pairing_request_accepts_and_persists_trust(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-123",
            },
            now=now + timedelta(seconds=5),
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["status"], "accepted")
        self.assertEqual(response_payload["desktop_name"], "Studio Mac")
        self.assertEqual(response_payload["device_uuid"], "ios-device-001")
        self.assertEqual(response_payload["transport"], "lan")
        self.assertTrue(response_payload["folder_path"].endswith("/Alice iPhone"))

        pairing_result = self._pairing_service.current_result()
        self.assertEqual(pairing_result.state, PairingResultState.ACCEPTED)
        self.assertEqual(pairing_result.device_name, "Alice iPhone")

        with create_db_conn(self._ctx) as conn:
            device_row = conn.execute(
                """
                SELECT device_uuid, platform, device_name, trust_key_b64
                FROM mobile_devices
                WHERE device_uuid = ?
                """,
                ("ios-device-001",),
            ).fetchone()
            self.assertIsNotNone(device_row)
            self.assertEqual(device_row["platform"], "ios")
            self.assertEqual(device_row["device_name"], "Alice iPhone")

            expected_key = derive_pairing_key_b64(
                session_id=session.session_id,
                one_time_passcode=token.one_time_passcode,
                device_uuid="ios-device-001",
                platform="ios",
                client_nonce="client-nonce-123",
                server_nonce=response_payload["server_nonce"],
                desktop_device_id=response_payload["desktop_device_id"],
            )
            self.assertEqual(device_row["trust_key_b64"], expected_key)

            folder_row = conn.execute(
                """
                SELECT folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-001",),
            ).fetchone()
            self.assertIsNotNone(folder_row)
            self.assertEqual(folder_row["folder_path"], response_payload["folder_path"])

            session_row = conn.execute(
                "SELECT status FROM mobile_backup_sessions WHERE session_id = ?",
                (session.session_id,),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "paired")

    def test_handle_pairing_request_rejects_expired_token(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-123",
            },
            now=now + timedelta(minutes=16),
        )

        self.assertEqual(status_code, 410)
        self.assertEqual(response_payload["status"], "expired")
        self.assertEqual(self._pairing_service.current_result().state, PairingResultState.EXPIRED)

    def test_is_ignorable_socket_disconnect_recognizes_client_disconnect_errors(self):
        self.assertTrue(_is_ignorable_socket_disconnect(OSError(errno.ENOTCONN, "Socket is not connected")))
        self.assertTrue(_is_ignorable_socket_disconnect(BrokenPipeError()))
        self.assertTrue(_is_ignorable_socket_disconnect(ConnectionResetError()))
        self.assertFalse(_is_ignorable_socket_disconnect(OSError(errno.EINVAL, "Invalid argument")))

    def test_live_pairing_http_endpoint_accepts_request(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._post_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-live-http-001",
                "device_name": "Live HTTP iPhone",
                "client_nonce": "live-http-nonce-001",
            }
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["status"], "accepted")
        self.assertEqual(response_payload["session_id"], session.session_id)

    def test_live_pairing_http_endpoint_returns_json_for_unhandled_error(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        with patch.object(self._pairing_service, "handle_pairing_request", side_effect=RuntimeError("boom")):
            status_code, response_payload = self._post_pairing_request(
                {
                    "schema": "dtis.mobile-pairing.v1",
                    "sid": session.session_id,
                    "opt": token.one_time_passcode,
                    "platform": "ios",
                    "device_uuid": "ios-live-http-err-001",
                    "device_name": "Live HTTP Error iPhone",
                    "client_nonce": "live-http-nonce-err-001",
                }
            )

        self.assertEqual(status_code, 500)
        self.assertEqual(response_payload["status"], "rejected")
        self.assertIn("Desktop failed while processing the pairing request.", response_payload["message"])

    def _post_pairing_request(self, payload: dict[str, str]) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            encoded_payload = json.dumps(payload).encode("utf-8")
            connection.request(
                "POST",
                endpoint.path,
                body=encoded_payload,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            response_body = response.read().decode("utf-8")
            return response.status, json.loads(response_body)
        finally:
            connection.close()
