import base64
import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import MobilePairingService, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.model.dts_db import create_db_conn
from tests.functional.mock_mobile_backup_client import MockBackupAsset, MockMobileBackupClient


class TestMobileBackupFlow(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._destination_root = Path(self._temp_dir.name) / "desktop-backups"
        self._destination_root.mkdir(parents=True, exist_ok=True)
        self._client_media_root = Path(self._temp_dir.name) / "client-media"
        self._client_media_root.mkdir(parents=True, exist_ok=True)

        self._ctx = BMContext(
            version=1,
            subfolder=f"functional-mobile-backup-{uuid.uuid4().hex}",
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

    def test_mock_mobile_client_pairs_and_uploads_sample_images_to_headless_server(self):
        pairing_started_at = datetime.now(timezone.utc)
        pairing_session = self._pairing_service.start_pairing_session(
            self._destination_root.as_posix(),
            now=pairing_started_at,
        )
        pairing_payload = pairing_session.token_for(MobilePlatform.IOS).payload

        sample_assets = self._create_sample_assets()
        backup_client = MockMobileBackupClient(
            pairing_payload=pairing_payload,
            device_uuid="functional-ios-device-001",
            device_name="Functional Test iPhone",
        )

        backup_result = backup_client.pair_and_backup(sample_assets)

        self.assertEqual(backup_result.start_response["status"], "accepted")
        self.assertEqual(backup_result.existence_response["status"], "checked")
        self.assertEqual(backup_result.existence_response["matches"], [])
        self.assertEqual(
            [asset_response["status"] for asset_response in backup_result.asset_responses],
            ["stored", "stored"],
        )
        self.assertEqual(backup_result.complete_response["status"], "completed")
        self.assertEqual(self._pairing_service.current_result().state, PairingResultState.ACCEPTED)

        paired_folder_path = Path(backup_result.pairing.folder_path)
        expected_first_path = paired_folder_path / "2026-04" / sample_assets[0].filename
        expected_second_path = paired_folder_path / "2026-04" / sample_assets[1].filename
        self.assertTrue(expected_first_path.exists())
        self.assertTrue(expected_second_path.exists())
        self.assertEqual(expected_first_path.read_bytes(), sample_assets[0].file_path.read_bytes())
        self.assertEqual(expected_second_path.read_bytes(), sample_assets[1].file_path.read_bytes())

        with create_db_conn(self._ctx) as conn:
            session_row = conn.execute(
                "SELECT status, ended_at FROM mobile_backup_sessions WHERE session_id = ?",
                (backup_result.pairing.session_id,),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "completed")
            self.assertIsNotNone(session_row["ended_at"])

    def test_mock_mobile_client_buckets_assets_by_created_month_not_updated_month(self):
        pairing_session = self._pairing_service.start_pairing_session(
            self._destination_root.as_posix(),
            now=datetime.now(timezone.utc),
        )
        pairing_payload = pairing_session.token_for(MobilePlatform.IOS).payload

        legacy_file_path = self._client_media_root / "IMG_1999.PNG"
        legacy_file_path.write_bytes(_SAMPLE_IMAGE_BYTES[0])
        legacy_asset = MockBackupAsset(
            asset_id="ph://functional-legacy-asset-001",
            file_path=legacy_file_path,
            filename=legacy_file_path.name,
            media_type="image",
            created_at=datetime(2025, 3, 14, 8, 15, tzinfo=timezone.utc),
            updated_at=datetime(2026, 4, 9, 12, 30, tzinfo=timezone.utc),
            asset_version="2026-04-09T12:30:00+00:00",
        )
        backup_client = MockMobileBackupClient(
            pairing_payload=pairing_payload,
            device_uuid="functional-ios-device-002",
            device_name="Functional Legacy iPhone",
        )

        backup_result = backup_client.pair_and_backup([legacy_asset])

        self.assertEqual(backup_result.asset_responses[0]["status"], "stored")
        self.assertEqual(backup_result.asset_responses[0]["local_relative_path"], "2025-03/IMG_1999.PNG")
        self.assertTrue((Path(backup_result.pairing.folder_path) / "2025-03" / legacy_asset.filename).exists())

    def _create_sample_assets(self) -> list[MockBackupAsset]:
        first_file_path = self._client_media_root / "IMG_0001.PNG"
        second_file_path = self._client_media_root / "IMG_0002.PNG"
        first_file_path.write_bytes(_SAMPLE_IMAGE_BYTES[0])
        second_file_path.write_bytes(_SAMPLE_IMAGE_BYTES[1])

        first_created_at = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        second_created_at = first_created_at + timedelta(minutes=5)
        return [
            MockBackupAsset(
                asset_id="ph://functional-asset-001",
                file_path=first_file_path,
                filename=first_file_path.name,
                media_type="image",
                created_at=first_created_at,
                updated_at=first_created_at + timedelta(minutes=1),
                asset_version=(first_created_at + timedelta(minutes=1)).isoformat(),
            ),
            MockBackupAsset(
                asset_id="ph://functional-asset-002",
                file_path=second_file_path,
                filename=second_file_path.name,
                media_type="image",
                created_at=second_created_at,
                updated_at=second_created_at + timedelta(minutes=1),
                asset_version=(second_created_at + timedelta(minutes=1)).isoformat(),
            ),
        ]


_SAMPLE_IMAGE_BYTES = (
    base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgJ/l7eQAAAAASUVORK5CYII="),
    base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAwMBAS8e0k0AAAAASUVORK5CYII="),
)


if __name__ == "__main__":
    unittest.main()
