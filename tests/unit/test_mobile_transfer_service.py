import errno
import hashlib
import http.client
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import MobilePairingService
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64, ensure_mobile_pairing_schema
from dt_image_search.mobile.mobile_trust_proof import derive_trust_proof_b64
from dt_image_search.mobile.mobile_transfer_service import (
    MOBILE_TRANSFER_ASSET_PROOF_PURPOSE,
    MOBILE_TRANSFER_ASSET_PATH,
    MOBILE_TRANSFER_COMPLETE_PROOF_PURPOSE,
    MOBILE_TRANSFER_COMPLETE_PATH,
    MOBILE_TRANSFER_DISK_FULL_EVENT,
    MOBILE_TRANSFER_FAILURE_CODE_DISK_FULL,
    MOBILE_TRANSFER_EXISTENCE_PROOF_PURPOSE,
    MOBILE_TRANSFER_EXISTENCE_PATH,
    MOBILE_TRANSFER_SCHEMA,
    MOBILE_TRANSFER_START_PROOF_PURPOSE,
    MOBILE_TRANSFER_STATE_UPDATED_EVENT,
    MOBILE_TRANSFER_STARTED_EVENT,
    MOBILE_TRANSFER_START_PATH,
)
from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
    TRANSFER_ASSET_STREAM_STATE_CHUNK,
    TRANSFER_ASSET_STREAM_STATE_COMPLETE,
    TRANSFER_ASSET_STREAM_STATE_FIELD,
    TRANSFER_ASSET_STREAM_STATE_START,
)
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.tools.dts_event_bus import default_bus


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

    def test_start_request_publishes_transfer_started_event(self):
        pairing_context = self._pair_device()
        received_events: list[dict[str, object]] = []
        transfer_state_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STARTED_EVENT,
            lambda **event: received_events.append(event),
        )
        self.addCleanup(subscription.dispose)
        transfer_state_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STATE_UPDATED_EVENT,
            lambda **event: transfer_state_events.append(event),
        )
        self.addCleanup(transfer_state_subscription.dispose)

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 3,
            },
        )

        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")
        self.assertEqual(
            received_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                }
            ],
        )
        self.assertEqual(
            transfer_state_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "transferring",
                }
            ],
        )

    def test_complete_request_publishes_transfer_state_updated_event(self):
        pairing_context = self._pair_device()
        transfer_state_events: list[dict[str, object]] = []
        transfer_state_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STATE_UPDATED_EVENT,
            lambda **event: transfer_state_events.append(event),
        )
        self.addCleanup(transfer_state_subscription.dispose)

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 0,
            },
        )
        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")

        complete_status, complete_response = self._post_json(
            MOBILE_TRANSFER_COMPLETE_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "transferred_count": 0,
                "failed_count": 0,
            },
        )
        self.assertEqual(complete_status, 200)
        self.assertEqual(complete_response["status"], "completed")
        self.assertEqual(
            transfer_state_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "transferring",
                },
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "transfer_completed",
                },
            ],
        )

    def test_complete_request_marks_stopped_session_and_clears_transferring_badge(self):
        pairing_context = self._pair_device()
        transfer_state_events: list[dict[str, object]] = []
        transfer_state_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STATE_UPDATED_EVENT,
            lambda **event: transfer_state_events.append(event),
        )
        self.addCleanup(transfer_state_subscription.dispose)

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 3,
            },
        )
        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")

        complete_status, complete_response = self._post_json(
            MOBILE_TRANSFER_COMPLETE_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "transferred_count": 1,
                "failed_count": 0,
                "interruption_reason": "stopped_by_user",
            },
        )
        self.assertEqual(complete_status, 200)
        self.assertEqual(complete_response["status"], "completed")
        self.assertIn("marked the transfer session as stopped", complete_response["message"])

        self.assertEqual(
            transfer_state_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "transferring",
                },
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "paired",
                },
            ],
        )

        with create_db_conn(self._ctx) as conn:
            session_row = conn.execute(
                "SELECT status, transferred_count FROM mobile_backup_sessions WHERE session_id = ?",
                (pairing_context["session_id"],),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "stopped_by_mobile")
            self.assertEqual(session_row["transferred_count"], 1)

            folder_row = conn.execute(
                "SELECT transfer_state FROM mobile_folders WHERE device_uuid = ?",
                (pairing_context["device_uuid"],),
            ).fetchone()
            self.assertIsNotNone(folder_row)
            self.assertEqual(folder_row["transfer_state"], "paired")

    def test_asset_upload_disk_full_marks_failed_and_publishes_notification_event(self):
        pairing_context = self._pair_device()
        transfer_state_events: list[dict[str, object]] = []
        disk_full_events: list[dict[str, object]] = []
        transfer_state_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STATE_UPDATED_EVENT,
            lambda **event: transfer_state_events.append(event),
        )
        self.addCleanup(transfer_state_subscription.dispose)
        disk_full_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_DISK_FULL_EVENT,
            lambda **event: disk_full_events.append(event),
        )
        self.addCleanup(disk_full_subscription.dispose)

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

        asset_bytes = b"image-bytes-disk-full"
        asset_metadata = {
            "schema": MOBILE_TRANSFER_SCHEMA,
            "session_id": pairing_context["session_id"],
            "device_uuid": pairing_context["device_uuid"],
            "trust_key": pairing_context["trust_key_b64"],
            "asset_id": "ph://asset-disk-full",
            "asset_version": "2026-04-09T12:30:00+00:00",
            "filename": "IMG_DISK_FULL.JPG",
            "media_type": "image",
            "created_at": "2026-04-09T12:00:00+00:00",
            "updated_at": "2026-04-09T12:30:00+00:00",
        }
        with patch(
            "dt_image_search.mobile.mobile_transfer_service._move_staged_asset_to_folder",
            side_effect=OSError(errno.ENOSPC, "No space left on device"),
        ):
            upload_status, upload_response = self._post_asset(
                asset_metadata=asset_metadata,
                asset_bytes=asset_bytes,
            )

        self.assertEqual(upload_status, 507)
        self.assertEqual(upload_response["status"], "rejected")
        self.assertEqual(upload_response["failure_code"], MOBILE_TRANSFER_FAILURE_CODE_DISK_FULL)
        self.assertIn("storage is full", upload_response["message"])

        self.assertEqual(
            transfer_state_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "transferring",
                },
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "transfer_state": "failed",
                },
            ],
        )
        self.assertEqual(
            disk_full_events,
            [
                {
                    "session_id": pairing_context["session_id"],
                    "device_uuid": pairing_context["device_uuid"],
                    "folder_path": pairing_context["folder_path"],
                    "message": "Desktop storage is full. Free up disk space on this PC and retry the mobile backup.",
                }
            ],
        )

        with create_db_conn(self._ctx) as conn:
            session_row = conn.execute(
                "SELECT status, ended_at, failed_count FROM mobile_backup_sessions WHERE session_id = ?",
                (pairing_context["session_id"],),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "failed")
            self.assertIsNotNone(session_row["ended_at"])
            self.assertEqual(session_row["failed_count"], 0)

            folder_row = conn.execute(
                "SELECT transfer_state FROM mobile_folders WHERE device_uuid = ?",
                (pairing_context["device_uuid"],),
            ).fetchone()
            self.assertIsNotNone(folder_row)
            self.assertEqual(folder_row["transfer_state"], "failed")

    def test_live_transfer_http_endpoints_skip_by_signature_tuple_for_different_asset_id(self):
        pairing_context = self._pair_device()

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 2,
            },
        )
        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")

        asset_bytes = b"image-bytes-001"
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
            **self._signature_metadata_fields(asset_bytes),
        }
        stored_status, stored_response = self._post_asset(
            asset_metadata=asset_metadata,
            asset_bytes=asset_bytes,
        )
        self.assertEqual(stored_status, 200)
        self.assertEqual(stored_response["status"], "stored")

        duplicate_metadata = dict(asset_metadata)
        duplicate_metadata["asset_id"] = "ph://asset-duplicate"
        duplicate_metadata["asset_version"] = "2026-04-09T13:30:00+00:00"
        skipped_status, skipped_response = self._post_asset(
            asset_metadata=duplicate_metadata,
            asset_bytes=asset_bytes,
        )
        self.assertEqual(skipped_status, 200)
        self.assertEqual(skipped_response["status"], "skipped")
        self.assertEqual(skipped_response["local_relative_path"], stored_response["local_relative_path"])

        with create_db_conn(self._ctx) as conn:
            asset_count_row = conn.execute(
                "SELECT COUNT(*) AS asset_count FROM mobile_assets WHERE device_uuid = ?",
                (pairing_context["device_uuid"],),
            ).fetchone()
            self.assertIsNotNone(asset_count_row)
            self.assertEqual(asset_count_row["asset_count"], 1)

    def test_live_transfer_existence_endpoint_returns_batch_matches_for_signature_tuples(self):
        pairing_context = self._pair_device()

        start_status, start_response = self._post_json(
            MOBILE_TRANSFER_START_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "total_assets": 2,
            },
        )
        self.assertEqual(start_status, 200)
        self.assertEqual(start_response["status"], "accepted")

        asset_bytes = b"image-bytes-lookup"
        created_at = "2026-04-09T12:00:00+00:00"
        uploaded_asset_metadata = {
            "schema": MOBILE_TRANSFER_SCHEMA,
            "session_id": pairing_context["session_id"],
            "device_uuid": pairing_context["device_uuid"],
            "trust_key": pairing_context["trust_key_b64"],
            "asset_id": "ph://asset-lookup-source",
            "asset_version": "2026-04-09T12:30:00+00:00",
            "filename": "IMG_0002.JPG",
            "media_type": "image",
            "created_at": created_at,
            "updated_at": "2026-04-09T12:30:00+00:00",
            **self._signature_metadata_fields(asset_bytes),
        }
        stored_status, stored_response = self._post_asset(
            asset_metadata=uploaded_asset_metadata,
            asset_bytes=asset_bytes,
        )
        self.assertEqual(stored_status, 200)
        self.assertEqual(stored_response["status"], "stored")

        existence_status, existence_response = self._post_json(
            MOBILE_TRANSFER_EXISTENCE_PATH,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_context["session_id"],
                "device_uuid": pairing_context["device_uuid"],
                "trust_key": pairing_context["trust_key_b64"],
                "assets": [
                    {
                        "asset_id": "ph://asset-lookup-match",
                        "created_at": created_at,
                        **self._signature_metadata_fields(asset_bytes),
                    },
                    {
                        "asset_id": "ph://asset-lookup-miss",
                        "created_at": created_at,
                        **self._signature_metadata_fields(b"image-bytes-missing"),
                    },
                ],
            },
        )
        self.assertEqual(existence_status, 200)
        self.assertEqual(existence_response["status"], "checked")
        self.assertEqual(
            existence_response["matches"],
            [
                {
                    "asset_id": "ph://asset-lookup-match",
                    "local_relative_path": stored_response["local_relative_path"],
                }
            ],
        )

    def test_ensure_mobile_pairing_schema_adds_signature_columns_to_legacy_mobile_assets_table(self):
        conn = sqlite3.connect(":memory:")
        self.addCleanup(conn.close)

        conn.executescript(
            """
            CREATE TABLE mobile_assets (
                device_uuid TEXT NOT NULL,
                remote_asset_id TEXT NOT NULL,
                remote_asset_version TEXT,
                local_relative_path TEXT NOT NULL,
                last_transferred_at TEXT NOT NULL,
                PRIMARY KEY (device_uuid, remote_asset_id)
            );
            """
        )

        ensure_mobile_pairing_schema(conn)

        table_info = conn.execute("PRAGMA table_info(mobile_assets)").fetchall()
        column_names = {row[1] for row in table_info}
        self.assertIn("content_sha1", column_names)
        self.assertIn("file_size_bytes", column_names)
        self.assertIn("asset_created_at", column_names)

        index_rows = conn.execute("PRAGMA index_list(mobile_assets)").fetchall()
        index_names = {row[1] for row in index_rows}
        self.assertIn("idx_mobile_assets_device_signature", index_names)

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
            platform="ios",
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
            normalized_payload = self._normalize_authenticated_payload(
                payload,
                purpose=self._proof_purpose_for_path(path),
            )
            encoded_payload = json.dumps(normalized_payload).encode("utf-8")
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
        request_id = uuid.uuid4().hex
        start_payload = dict(asset_metadata)
        start_payload[TRANSFER_ASSET_STREAM_STATE_FIELD] = TRANSFER_ASSET_STREAM_STATE_START
        start_payload["chunk_size"] = TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES

        start_status, _ = self._post_transfer_asset_json(
            endpoint=endpoint,
            request_id=request_id,
            stream_state=TRANSFER_ASSET_STREAM_STATE_START,
            payload=start_payload,
        )
        self.assertEqual(start_status, 200)

        chunk_start = 0
        while chunk_start < len(asset_bytes):
            chunk_end = min(
                chunk_start + TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
                len(asset_bytes),
            )
            chunk = asset_bytes[chunk_start:chunk_end]
            chunk_start = chunk_end
            chunk_status, _ = self._post_transfer_asset_binary_chunk(
                endpoint=endpoint,
                request_id=request_id,
                chunk=chunk,
            )
            self.assertEqual(chunk_status, 200)

        return self._post_transfer_asset_json(
            endpoint=endpoint,
            request_id=request_id,
            stream_state=TRANSFER_ASSET_STREAM_STATE_COMPLETE,
            payload={
                "schema": MOBILE_TRANSFER_SCHEMA,
                TRANSFER_ASSET_STREAM_STATE_FIELD: TRANSFER_ASSET_STREAM_STATE_COMPLETE,
            },
        )

    def _post_transfer_asset_json(
        self,
        *,
        endpoint,
        request_id: str,
        stream_state: str,
        payload: dict[str, object],
    ) -> tuple[int, dict[str, object]]:
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            normalized_payload = self._normalize_authenticated_payload(
                payload,
                purpose=MOBILE_TRANSFER_ASSET_PROOF_PURPOSE,
            )
            encoded_payload = json.dumps(normalized_payload, separators=(",", ":")).encode("utf-8")
            connection.request(
                "POST",
                (
                    f"{MOBILE_TRANSFER_ASSET_PATH}?request_id={request_id}"
                    f"&{TRANSFER_ASSET_STREAM_STATE_FIELD}={stream_state}"
                ),
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

    def _post_transfer_asset_binary_chunk(
        self,
        *,
        endpoint,
        request_id: str,
        chunk: bytes,
    ) -> tuple[int, dict[str, object]]:
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            connection.request(
                "POST",
                (
                    f"{MOBILE_TRANSFER_ASSET_PATH}?request_id={request_id}"
                    f"&{TRANSFER_ASSET_STREAM_STATE_FIELD}={TRANSFER_ASSET_STREAM_STATE_CHUNK}"
                ),
                body=chunk,
                headers={
                    "Content-Type": "application/octet-stream",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            return response.status, json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()

    @staticmethod
    def _signature_metadata_fields(asset_bytes: bytes) -> dict[str, object]:
        return {
            "sha1": hashlib.sha1(asset_bytes).hexdigest(),
            "file_size": len(asset_bytes),
        }

    @staticmethod
    def _normalize_authenticated_payload(
        payload: dict[str, object],
        *,
        purpose: str | None,
    ) -> dict[str, object]:
        normalized_payload = dict(payload)
        raw_trust_key = normalized_payload.pop("trust_key", None)
        if isinstance(raw_trust_key, str) and raw_trust_key and purpose is not None:
            normalized_payload["trust_proof"] = derive_trust_proof_b64(
                trust_key_b64=raw_trust_key,
                purpose=purpose,
                schema=str(normalized_payload.get("schema", "")),
                session_id=str(normalized_payload.get("session_id", "")),
                device_uuid=str(normalized_payload.get("device_uuid", "")),
            )
        return normalized_payload

    @staticmethod
    def _proof_purpose_for_path(path: str) -> str | None:
        if path == MOBILE_TRANSFER_START_PATH:
            return MOBILE_TRANSFER_START_PROOF_PURPOSE
        if path == MOBILE_TRANSFER_EXISTENCE_PATH:
            return MOBILE_TRANSFER_EXISTENCE_PROOF_PURPOSE
        if path == MOBILE_TRANSFER_COMPLETE_PATH:
            return MOBILE_TRANSFER_COMPLETE_PROOF_PURPOSE
        return None


if __name__ == "__main__":
    unittest.main()
