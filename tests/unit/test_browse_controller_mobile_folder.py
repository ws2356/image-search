import importlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timezone
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from PySide6.QtCore import Qt
from PySide6.QtTest import QSignalSpy
from PySide6.QtWidgets import QApplication

from dt_image_search.bm_context import BMContext
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_BACKUP_SESSION_STATUS_COMPLETED,
    MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
    MOBILE_TRANSFER_STATE_COMPLETED,
    MOBILE_TRANSFER_STATE_TRANSFERRING,
)
from dt_image_search.model.dts_db import create_db_conn, insert_folder


_APP = QApplication.instance() or QApplication([])
browse_controller_module = importlib.import_module("dt_image_search.browse.BrowseController")


class _DummySubscription:
    def dispose(self):
        return None


class TestBrowseControllerMobileFolder(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"browse-mobile-tests-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{self._ctx.subfolder}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

    def test_ensure_folder_registered_adds_mobile_root_folder_to_live_tree(self):
        with self._controller_context() as (controller, add_folder_mock, add_index_worker_mock):
            folder_path = (Path(self._temp_dir.name) / "Alice iPhone").resolve()
            folder_path.mkdir(parents=True, exist_ok=True)
            updated_at = datetime.now(timezone.utc).isoformat()
            with create_db_conn(ctx=self._ctx) as conn:
                folder = insert_folder(conn, folder_path.as_posix())
                self.assertIsNotNone(folder)
                conn.execute(
                    """
                    INSERT INTO mobile_devices (
                        device_uuid,
                        platform,
                        device_name,
                        trust_key_b64,
                        paired_at,
                        last_seen_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    ("device-root-001", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
                )
                conn.execute(
                    """
                    INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    (folder.id, "device-root-001", MOBILE_TRANSFER_STATE_TRANSFERRING, updated_at),
                )
                conn.commit()

            selection_spy = QSignalSpy(controller.folder_selection_signal.select_folder)

            controller.ensure_folder_registered(folder_path.as_posix(), select_folder=True)

            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertIsNotNone(folder_item.parent())
            self.assertEqual(folder_item.parent().text(), "MOBILE")
            self.assertEqual(selection_spy.count(), 1)
            selected_item = selection_spy.at(0)[0]
            self.assertEqual(selected_item.data(Qt.UserRole), folder_path.as_posix())
            add_folder_mock.assert_called_once_with(folder_path.as_posix())
            add_index_worker_mock.assert_called_once()
            self.assertEqual(add_index_worker_mock.call_args.kwargs["folder"].path, folder_path.as_posix())

    def test_ensure_folder_registered_reveals_mobile_child_under_existing_root(self):
        destination_parent = (Path(self._temp_dir.name) / "Mobile Backups").resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        with create_db_conn(ctx=self._ctx) as conn:
            insert_folder(conn, destination_parent.as_posix())

        with self._controller_context() as (controller, add_folder_mock, add_index_worker_mock):
            folder_path = (destination_parent / "Alice iPhone").resolve()
            folder_path.mkdir(parents=True, exist_ok=True)
            updated_at = datetime.now(timezone.utc).isoformat()
            with create_db_conn(ctx=self._ctx) as conn:
                folder = insert_folder(conn, folder_path.as_posix())
                self.assertIsNotNone(folder)
                conn.execute(
                    """
                    INSERT INTO mobile_devices (
                        device_uuid,
                        platform,
                        device_name,
                        trust_key_b64,
                        paired_at,
                        last_seen_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    ("device-child-001", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
                )
                conn.execute(
                    """
                    INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    (folder.id, "device-child-001", MOBILE_TRANSFER_STATE_TRANSFERRING, updated_at),
                )
                conn.commit()

            selection_spy = QSignalSpy(controller.folder_selection_signal.select_folder)

            controller.ensure_folder_registered(folder_path.as_posix(), select_folder=True)

            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertIsNotNone(folder_item.parent())
            self.assertEqual(folder_item.parent().text(), "MOBILE")
            self.assertEqual(selection_spy.count(), 1)
            selected_item = selection_spy.at(0)[0]
            self.assertEqual(selected_item.data(Qt.UserRole), folder_path.as_posix())
            add_folder_mock.assert_called_once_with(folder_path.as_posix())
            add_index_worker_mock.assert_called_once()

    def test_mobile_folder_badge_tracks_polled_db_transfer_state(self):
        folder_path = (Path(self._temp_dir.name) / "Alice iPhone").resolve()
        folder_path.mkdir(parents=True, exist_ok=True)
        updated_at = datetime.now(timezone.utc).isoformat()

        with create_db_conn(ctx=self._ctx) as conn:
            folder = insert_folder(conn, folder_path.as_posix())
            self.assertIsNotNone(folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                ("device-001", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (folder.id, "device-001", MOBILE_TRANSFER_STATE_TRANSFERRING, updated_at),
            )
            conn.execute(
                """
                INSERT INTO mobile_backup_sessions (
                    session_id,
                    device_uuid,
                    folder_id,
                    status,
                    transferred_count,
                    failed_count,
                    started_at,
                    paired_at,
                    ended_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "session-001",
                    "device-001",
                    folder.id,
                    MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
                    6,
                    0,
                    updated_at,
                    updated_at,
                    None,
                ),
            )
            conn.commit()

        with self._controller_context() as (controller, _add_folder_mock, _add_index_worker_mock):
            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertEqual(folder_item.text(), "Alice iPhone")
            self.assertEqual(
                folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE),
                MOBILE_TRANSFER_STATE_TRANSFERRING,
            )
            self.assertEqual(folder_item.data(controller.folder_list_model().MOBILE_TRANSFERRED_COUNT_ROLE), 6)
            self.assertIsNone(folder_item.data(controller.folder_list_model().MOBILE_LAST_BACKUP_AT_ROLE))

            completed_at = datetime.now(timezone.utc).isoformat()
            with create_db_conn(ctx=self._ctx) as conn:
                conn.execute(
                    """
                    UPDATE mobile_folders
                    SET transfer_state = ?, transfer_state_updated_at = ?
                    WHERE folder_id = ?
                    """,
                    (MOBILE_TRANSFER_STATE_COMPLETED, completed_at, folder.id),
                )
                conn.execute(
                    """
                    UPDATE mobile_backup_sessions
                    SET status = ?, ended_at = ?
                    WHERE session_id = ? AND device_uuid = ?
                    """,
                    (
                        MOBILE_BACKUP_SESSION_STATUS_COMPLETED,
                        completed_at,
                        "session-001",
                        "device-001",
                    ),
                )
                conn.commit()

            controller._on_mobile_transfer_status_poll_timeout()
            self.assertEqual(folder_item.text(), "Alice iPhone")
            self.assertIsNone(folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE))
            self.assertEqual(folder_item.data(controller.folder_list_model().MOBILE_LAST_BACKUP_AT_ROLE), completed_at)

    def test_mobile_folder_poll_timer_runs_only_while_controller_is_active(self):
        folder_path = (Path(self._temp_dir.name) / "Alice iPhone").resolve()
        folder_path.mkdir(parents=True, exist_ok=True)
        updated_at = datetime.now(timezone.utc).isoformat()

        with create_db_conn(ctx=self._ctx) as conn:
            folder = insert_folder(conn, folder_path.as_posix())
            self.assertIsNotNone(folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                ("device-002", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (folder.id, "device-002", MOBILE_TRANSFER_STATE_COMPLETED, updated_at),
            )
            conn.execute(
                """
                INSERT INTO mobile_backup_sessions (
                    session_id,
                    device_uuid,
                    folder_id,
                    status,
                    transferred_count,
                    failed_count,
                    started_at,
                    paired_at,
                    ended_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "session-002",
                    "device-002",
                    folder.id,
                    MOBILE_BACKUP_SESSION_STATUS_COMPLETED,
                    4,
                    0,
                    updated_at,
                    updated_at,
                    updated_at,
                ),
            )
            conn.commit()

        with self._controller_context() as (controller, _add_folder_mock, _add_index_worker_mock):
            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertFalse(controller._mobile_transfer_status_timer.isActive())
            self.assertIsNone(folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE))

            with create_db_conn(ctx=self._ctx) as conn:
                conn.execute(
                    """
                    UPDATE mobile_folders
                    SET transfer_state = ?, transfer_state_updated_at = ?
                    WHERE folder_id = ?
                    """,
                    (MOBILE_TRANSFER_STATE_TRANSFERRING, datetime.now(timezone.utc).isoformat(), folder.id),
                )
                conn.execute(
                    """
                    UPDATE mobile_backup_sessions
                    SET status = ?
                    WHERE session_id = ? AND device_uuid = ?
                    """,
                    (
                        MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
                        "session-002",
                        "device-002",
                    ),
                )
                conn.commit()

            self.assertIsNone(folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE))

            controller.is_active = True
            self.assertTrue(controller._mobile_transfer_status_timer.isActive())
            self.assertEqual(
                folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE),
                MOBILE_TRANSFER_STATE_TRANSFERRING,
            )

            controller.is_active = False
            self.assertFalse(controller._mobile_transfer_status_timer.isActive())

    def test_folder_tree_is_flat_when_mobile_folder_feature_is_disabled(self):
        root_folder = (Path(self._temp_dir.name) / "Desktop Photos").resolve()
        root_folder.mkdir(parents=True, exist_ok=True)
        with create_db_conn(ctx=self._ctx) as conn:
            inserted_folder = insert_folder(conn, root_folder.as_posix())
            self.assertIsNotNone(inserted_folder)

        with self._controller_context(mobile_feature_enabled=False) as (controller, _add_folder_mock, _add_index_worker_mock):
            model = controller.folder_list_model()
            self.assertEqual(model.rowCount(), 1)
            top_level_item = model.item(0, 0)
            self.assertIsNotNone(top_level_item)
            self.assertEqual(top_level_item.data(Qt.UserRole), root_folder.as_posix())
            self.assertFalse(bool(top_level_item.data(model.SECTION_ROLE)))
            self.assertTrue(model.is_top_level_folder_item(top_level_item))

    def test_folder_tree_forwards_subfolder_insert_and_remove_without_model_reset(self):
        root_folder = (Path(self._temp_dir.name) / "Desktop Photos").resolve()
        root_folder.mkdir(parents=True, exist_ok=True)
        with create_db_conn(ctx=self._ctx) as conn:
            inserted_folder = insert_folder(conn, root_folder.as_posix())
            self.assertIsNotNone(inserted_folder)

        with self._controller_context(mobile_feature_enabled=False) as (controller, _add_folder_mock, _add_index_worker_mock):
            model = controller.folder_list_model()
            top_level_item = model.item(0, 0)
            self.assertIsNotNone(top_level_item)
            root_index = model.indexFromItem(top_level_item)
            self.assertTrue(root_index.isValid())
            if model.canFetchMore(root_index):
                model.fetchMore(root_index)
            _APP.processEvents()

            inserted_spy = QSignalSpy(model.rowsInserted)
            removed_spy = QSignalSpy(model.rowsRemoved)
            reset_spy = QSignalSpy(model.modelReset)

            child_folder = (root_folder / "2026-04").resolve()
            child_folder.mkdir(parents=True, exist_ok=True)
            self.assertTrue(inserted_spy.wait(2000))
            self.assertIsNotNone(model.find_folder_item(child_folder.as_posix()))
            self.assertEqual(reset_spy.count(), 0)

            child_folder.rmdir()
            self.assertTrue(removed_spy.wait(2000))
            self.assertIsNone(model.find_folder_item(child_folder.as_posix()))
            self.assertEqual(reset_spy.count(), 0)

    def test_mobile_root_moves_between_sections_without_model_reset(self):
        root_folder = (Path(self._temp_dir.name) / "Alice iPhone").resolve()
        root_folder.mkdir(parents=True, exist_ok=True)
        with create_db_conn(ctx=self._ctx) as conn:
            inserted_folder = insert_folder(conn, root_folder.as_posix())
            self.assertIsNotNone(inserted_folder)
            folder_id = int(inserted_folder.id)

        with self._controller_context() as (controller, _add_folder_mock, _add_index_worker_mock):
            model = controller.folder_list_model()
            folder_item = model.find_folder_item(root_folder.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertEqual(folder_item.parent().text(), "LOCAL")

            moved_spy = QSignalSpy(model.rowsMoved)
            reset_spy = QSignalSpy(model.modelReset)

            updated_at = datetime.now(timezone.utc).isoformat()
            with create_db_conn(ctx=self._ctx) as conn:
                conn.execute(
                    """
                    INSERT INTO mobile_devices (
                        device_uuid,
                        platform,
                        device_name,
                        trust_key_b64,
                        paired_at,
                        last_seen_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    ("device-move-001", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
                )
                conn.execute(
                    """
                    INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    (folder_id, "device-move-001", MOBILE_TRANSFER_STATE_TRANSFERRING, updated_at),
                )
                conn.commit()

            controller._refresh_mobile_transfer_states()
            self.assertEqual(moved_spy.count(), 1)
            self.assertEqual(reset_spy.count(), 0)
            self.assertEqual(folder_item.parent().text(), "MOBILE")

            with create_db_conn(ctx=self._ctx) as conn:
                conn.execute("DELETE FROM mobile_folders WHERE folder_id = ?", (folder_id,))
                conn.execute("DELETE FROM mobile_devices WHERE device_uuid = ?", ("device-move-001",))
                conn.commit()

            controller._refresh_mobile_transfer_states()
            self.assertEqual(moved_spy.count(), 2)
            self.assertEqual(reset_spy.count(), 0)
            self.assertEqual(folder_item.parent().text(), "LOCAL")

    def test_mobile_root_poll_noop_does_not_reset_or_move_tree(self):
        root_folder = (Path(self._temp_dir.name) / "Alice iPhone").resolve()
        root_folder.mkdir(parents=True, exist_ok=True)
        updated_at = datetime.now(timezone.utc).isoformat()
        with create_db_conn(ctx=self._ctx) as conn:
            inserted_folder = insert_folder(conn, root_folder.as_posix())
            self.assertIsNotNone(inserted_folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                ("device-noop-001", "ios", "Alice iPhone", "trust-key", updated_at, updated_at),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (int(inserted_folder.id), "device-noop-001", MOBILE_TRANSFER_STATE_TRANSFERRING, updated_at),
            )
            conn.commit()

        with self._controller_context() as (controller, _add_folder_mock, _add_index_worker_mock):
            model = controller.folder_list_model()
            folder_item = model.find_folder_item(root_folder.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertEqual(folder_item.parent().text(), "MOBILE")

            moved_spy = QSignalSpy(model.rowsMoved)
            reset_spy = QSignalSpy(model.modelReset)

            controller._refresh_mobile_transfer_states()

            self.assertEqual(moved_spy.count(), 0)
            self.assertEqual(reset_spy.count(), 0)
            self.assertEqual(folder_item.parent().text(), "MOBILE")

    def _controller_context(self, *, mobile_feature_enabled: bool = True):
        return _ControllerContext(self._ctx, mobile_feature_enabled=mobile_feature_enabled)


class _ControllerContext:
    def __init__(self, ctx: BMContext, *, mobile_feature_enabled: bool):
        self._ctx = ctx
        self._mobile_feature_enabled = mobile_feature_enabled
        self._patches = []
        self._controller = None
        self._add_folder_mock = None
        self._add_index_worker_mock = None

    def __enter__(self):
        self._patches = [
            patch.object(browse_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch("dt_image_search.browse.BrowseController.add_folder"),
            patch("dt_image_search.browse.BrowseController.add_index_worker"),
            patch(
                "dt_image_search.browse.BrowseController.is_mobile_folder_enabled",
                return_value=self._mobile_feature_enabled,
            ),
        ]
        subscribe_patch, add_folder_patch, add_index_worker_patch, mobile_flag_patch = self._patches
        subscribe_patch.start()
        self._add_folder_mock = add_folder_patch.start()
        self._add_index_worker_mock = add_index_worker_patch.start()
        mobile_flag_patch.start()
        self._controller = BrowseController(ctx=self._ctx)
        return self._controller, self._add_folder_mock, self._add_index_worker_mock

    def __exit__(self, exc_type, exc, tb):
        if self._controller is not None:
            self._controller.is_active = False
        for patcher in reversed(self._patches):
            patcher.stop()
        self._patches = []
        return False


if __name__ == "__main__":
    unittest.main()
