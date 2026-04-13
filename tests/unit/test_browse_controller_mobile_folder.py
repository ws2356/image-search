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
from PySide6.QtWidgets import QApplication

from dt_image_search.bm_context import BMContext
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.mobile.mobile_pairing_store import (
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

            selected_paths: list[str] = []
            controller.folder_selection_signal.select_folder.connect(
                lambda item: selected_paths.append(item.data(Qt.UserRole))
            )

            controller.ensure_folder_registered(folder_path.as_posix())

            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertIsNotNone(folder_item.parent())
            self.assertEqual(folder_item.parent().text(), "MOBILE")
            self.assertEqual(selected_paths, [folder_path.as_posix()])
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

            selected_paths: list[str] = []
            controller.folder_selection_signal.select_folder.connect(
                lambda item: selected_paths.append(item.data(Qt.UserRole))
            )

            controller.ensure_folder_registered(folder_path.as_posix())

            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertIsNotNone(folder_item.parent())
            self.assertEqual(folder_item.parent().text(), "MOBILE")
            self.assertEqual(selected_paths, [folder_path.as_posix()])
            add_folder_mock.assert_called_once_with(folder_path.as_posix())
            add_index_worker_mock.assert_called_once()

    def test_mobile_folder_badge_is_visible_only_for_transferring_state(self):
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
            conn.commit()

        with self._controller_context() as (controller, _add_folder_mock, _add_index_worker_mock):
            folder_item = controller.folder_list_model().find_folder_item(folder_path.as_posix())
            self.assertIsNotNone(folder_item)
            self.assertEqual(folder_item.text(), "Alice iPhone")
            self.assertEqual(folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE), MOBILE_TRANSFER_STATE_TRANSFERRING)

            with create_db_conn(ctx=self._ctx) as conn:
                conn.execute(
                    "UPDATE mobile_folders SET transfer_state = ? WHERE device_uuid = ?",
                    (MOBILE_TRANSFER_STATE_COMPLETED, "device-001"),
                )
                conn.commit()

            controller._refresh_mobile_transfer_states()
            self.assertEqual(folder_item.text(), "Alice iPhone")
            self.assertEqual(folder_item.data(controller.folder_list_model().MOBILE_TRANSFER_STATE_ROLE), MOBILE_TRANSFER_STATE_COMPLETED)

    def _controller_context(self):
        return _ControllerContext(self._ctx)


class _ControllerContext:
    def __init__(self, ctx: BMContext):
        self._ctx = ctx
        self._patches = []
        self._controller = None
        self._add_folder_mock = None
        self._add_index_worker_mock = None

    def __enter__(self):
        self._patches = [
            patch.object(browse_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch("dt_image_search.browse.BrowseController.add_folder"),
            patch("dt_image_search.browse.BrowseController.add_index_worker"),
        ]
        subscribe_patch, add_folder_patch, add_index_worker_patch = self._patches
        subscribe_patch.start()
        self._add_folder_mock = add_folder_patch.start()
        self._add_index_worker_mock = add_index_worker_patch.start()
        self._controller = BrowseController(ctx=self._ctx)
        return self._controller, self._add_folder_mock, self._add_index_worker_mock

    def __exit__(self, exc_type, exc, tb):
        for patcher in reversed(self._patches):
            patcher.stop()
        self._patches = []
        return False


if __name__ == "__main__":
    unittest.main()
