import base64
import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import MobilePairingService
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64
from dt_image_search.mobile.mobile_transfer_service import (
    MOBILE_TRANSFER_ASSET_PATH,
    MOBILE_TRANSFER_COMPLETE_PATH,
    MOBILE_TRANSFER_SCHEMA,
    MOBILE_TRANSFER_START_PATH,
)
from dt_image_search.model.dts_db import create_db_conn


class TestMobileTransferService(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"transfer-tests-{uuid.uuid4().hex}",
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

    def test_live_transfer_http_endpoints_store_skip_and_complete_session(self):
        pairing_context = self._pair_device()

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 1,
            },
        )
        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")

        asset_metadata = {
            "schema": MOBILE_TRANSFER_SCHEMA,
            "session_id": pairing_context["session_id"],
            "device_uuid": pairing_context["device_uuid"],
            "trust_key": pairing_context["trust_key_b64"],
            "asset_id": "ph://asset-001",
            "asset_version": "2026-04-09T12:30:00+00:00",
            "filename": "IMG_0001.JPG",
            "media_type": "image",
            "created_at": "2026-04-09T12:00:00+00:00",
            "updated_at": "2026-04-09T12:30:00+00:00",
        }
        stored_status, stored_response = self._post_asset(
            asset_metadata=asset_metadata,
            asset_bytes=b"image-bytes-001",
        )
        self.assertEqual(stored_status, 200)
        self.assertEqual(stored_response["status"], "stored")
        self.assertEqual(stored_response["local_relative_path"], "2026-04/IMG_0001.JPG")

        stored_path = Path(pairing_context["folder_path"]) / stored_response["local_relative_path"]
        self.assertTrue(stored_path.exists())
        self.assertEqual(stored_path.read_bytes(), b"image-bytes-001")

        skipped_status, skipped_response = self._post_asset(
            asset_metadata=asset_metadata,
            asset_bytes=b"image-bytes-ignored",
        )
        self.assertEqual(skipped_status, 200)
        self.assertEqual(skipped_response["status"], "skipped")
        self.assertEqual(skipped_response["local_relative_path"], "2026-04/IMG_0001.JPG")
        self.assertEqual(stored_path.read_bytes(), b"image-bytes-001")

        updated_metadata = dict(asset_metadata)
        updated_metadata["asset_version"] = "2026-04-09T13:00:00+00:00"
        updated_status, updated_response = self._post_asset(
            asset_metadata=updated_metadata,
            asset_bytes=b"image-bytes-002",
        )
        self.assertEqual(updated_status, 200)
        self.assertEqual(updated_response["status"], "stored")
        self.assertEqual(updated_response["local_relative_path"], "2026-04/IMG_0001-2.JPG")
        self.assertEqual(
            (Path(pairing_context["folder_path"]) / updated_response["local_relative_path"]).read_bytes(),
            b"image-bytes-002",
        )

        complete_status, complete_response = self._post_json(
            MOBILE_TRANSFER_COMPLETE_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "transferred_count": 2,
                "failed_count": 0,
            },
        )
        self.assertEqual(complete_status, 200)
        self.assertEqual(complete_response["status"], "completed")

        with create_db_conn(self._ctx) as conn:
            asset_row = conn.execute(
                """
                SELECT remote_asset_version, local_relative_path
                FROM mobile_assets
                WHERE device_uuid = ? AND remote_asset_id = ?
                """,
                (pairing_context["device_uuid"], "ph://asset-001"),
            ).fetchone()
            self.assertIsNotNone(asset_row)
            self.assertEqual(asset_row["remote_asset_version"], "2026-04-09T13:00:00+00:00")
            self.assertEqual(asset_row["local_relative_path"], "2026-04/IMG_0001-2.JPG")

            session_row = conn.execute(
                "SELECT status, ended_at FROM mobile_backup_sessions WHERE session_id = ?",
                (pairing_context["session_id"],),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "completed")
            self.assertIsNotNone(session_row["ended_at"])

            folder_row = conn.execute(
                "SELECT transfer_state FROM mobile_folders WHERE device_uuid = ?",
                (pairing_context["device_uuid"],),
            ).fetchone()
            self.assertIsNotNone(folder_row)
            self.assertEqual(folder_row["transfer_state"], "transfer_completed")

    def _pair_device(self) -> dict[str, str]:
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
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

        trust_key_b64 = derive_pairing_key_b64(
            session_id=session.session_id,
            one_time_passcode=token.one_time_passcode,
            device_uuid="ios-device-001",
            platform="ios",
            client_nonce="client-nonce-123",
            server_nonce=response_payload["server_nonce"],
            desktop_device_id=response_payload["desktop_device_id"],
        )
        return {
            "session_id": session.session_id,
            "device_uuid": "ios-device-001",
            "trust_key_b64": trust_key_b64,
            "folder_path": response_payload["folder_path"],
        }

    def _post_json(self, path: str, payload: dict[str, object]) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            encoded_payload = json.dumps(payload).encode("utf-8")
            connection.request(
                "POST",
                path,
                body=encoded_payload,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            return response.status, json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()

    def _post_asset(self, *, asset_metadata: dict[str, object], asset_bytes: bytes) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            encoded_metadata = base64.urlsafe_b64encode(
                json.dumps(asset_metadata, separators=(",", ":")).encode("utf-8")
            ).decode("ascii").rstrip("=")
            connection.request(
                "POST",
                f"{MOBILE_TRANSFER_ASSET_PATH}?meta={encoded_metadata}",
                body=asset_bytes,
                headers={
                    "Content-Type": "application/octet-stream",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            return response.status, json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
