import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

import watchdog.events

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.index.incremental_index_worker import _on_moved
from dt_image_search.model.dts_db import create_db_conn, get_file_by_path, get_folder_by_path, insert_file, insert_folder
from dt_image_search.tools.dts_util import normalized_folder_path


class TestIncrementalIndexWorkerMovedEvents(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"incremental-worker-tests-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{self._ctx.subfolder}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

    def test_on_moved_treats_external_to_internal_file_move_as_addition(self):
        root_path, _ = self._create_root_folder("Mobile Folder")
        destination_path = root_path / "incoming" / "IMG_0001.JPG"
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        destination_path.write_bytes(b"image-001")

        event = watchdog.events.FileMovedEvent(
            str(Path(self._temp_dir.name) / "tmp" / "upload.part"),
            destination_path.as_posix(),
        )

        with patch("dt_image_search.index.incremental_index_worker._on_created") as on_created_mock, patch(
            "dt_image_search.index.incremental_index_worker._on_deleted"
        ) as on_deleted_mock:
            _on_moved(self._ctx, [event])

        on_created_mock.assert_called_once()
        created_events = on_created_mock.call_args.args[1]
        self.assertEqual(len(created_events), 1)
        self.assertIsInstance(created_events[0], watchdog.events.FileCreatedEvent)
        self.assertEqual(created_events[0].src_path, destination_path.as_posix())
        on_deleted_mock.assert_not_called()

    def test_on_moved_treats_internal_to_external_file_move_as_deletion(self):
        root_path, folder = self._create_root_folder("Mobile Folder")
        source_path = root_path / "IMG_0001.JPG"
        source_path.write_bytes(b"image-001")
        with create_db_conn(ctx=self._ctx) as conn:
            insert_file(conn, source_path.as_posix(), folder.id)

        event = watchdog.events.FileMovedEvent(
            source_path.as_posix(),
            str(Path(self._temp_dir.name) / "tmp" / "IMG_0001.JPG"),
        )

        with patch("dt_image_search.index.incremental_index_worker._on_created") as on_created_mock, patch(
            "dt_image_search.index.incremental_index_worker._on_deleted"
        ) as on_deleted_mock:
            _on_moved(self._ctx, [event])

        on_created_mock.assert_not_called()
        on_deleted_mock.assert_called_once()
        deleted_events = on_deleted_mock.call_args.args[1]
        self.assertEqual(len(deleted_events), 1)
        self.assertIsInstance(deleted_events[0], watchdog.events.FileDeletedEvent)
        self.assertEqual(deleted_events[0].src_path, source_path.as_posix())

    def test_on_moved_keeps_internal_to_internal_file_move_as_rename(self):
        root_path, folder = self._create_root_folder("Mobile Folder")
        source_path = root_path / "IMG_0001.JPG"
        destination_path = root_path / "Renamed" / "IMG_0001.JPG"
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        source_path.write_bytes(b"image-001")
        with create_db_conn(ctx=self._ctx) as conn:
            insert_file(conn, source_path.as_posix(), folder.id)

        event = watchdog.events.FileMovedEvent(
            source_path.as_posix(),
            destination_path.as_posix(),
        )

        _on_moved(self._ctx, [event])

        with create_db_conn(ctx=self._ctx) as conn:
            self.assertIsNone(get_file_by_path(conn, source_path.as_posix()))
            renamed_file = get_file_by_path(conn, destination_path.as_posix())
            self.assertIsNotNone(renamed_file)
            self.assertEqual(renamed_file.folder_id, folder.id)

    def _create_root_folder(self, name: str):
        root_path = (Path(self._temp_dir.name) / name).resolve()
        root_path.mkdir(parents=True, exist_ok=True)
        with create_db_conn(ctx=self._ctx) as conn:
            insert_folder(conn, normalized_folder_path(root_path.as_posix()))
            folder = get_folder_by_path(conn, root_path.as_posix())
        self.assertIsNotNone(folder)
        return root_path, folder


if __name__ == "__main__":
    unittest.main()
