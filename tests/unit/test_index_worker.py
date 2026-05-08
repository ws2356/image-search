import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.index.index_worker import IndexWorker
from dt_image_search.model.dts_folder import Folder


class _FakeScandir:
    def __init__(self, entries):
        self._entries = entries

    def __enter__(self):
        return iter(self._entries)

    def __exit__(self, exc_type, exc, tb):
        return False


class _FakeDirEntry:
    def __init__(self, path: str, *, is_dir: bool, is_file: bool):
        self.path = path
        self._is_dir = is_dir
        self._is_file = is_file

    def is_dir(self, follow_symlinks: bool = True):
        return self._is_dir

    def is_file(self, follow_symlinks: bool = True):
        return self._is_file


class _ConnContext:
    def __init__(self, conn):
        self._conn = conn

    def __enter__(self):
        return self._conn

    def __exit__(self, exc_type, exc, tb):
        return False


class TestIndexWorkerTraversalErrors(unittest.TestCase):
    def test_run_impl_skips_inaccessible_subfolder_and_marks_partial_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root_path = os.path.join(temp_dir, "root").replace("\\", "/")
            inaccessible_dir = os.path.join(root_path, "locked").replace("\\", "/")
            image_path = os.path.join(root_path, "IMG_0001.jpg").replace("\\", "/")
            folder = Folder(id=42, path=root_path, status=0, added_at="2026-01-01T00:00:00")
            conn = MagicMock()
            worker = IndexWorker(ctx=MagicMock(), folder=folder)
            status_bar_mock = MagicMock()

            def _scandir(path):
                if path == root_path:
                    return _FakeScandir(
                        [
                            _FakeDirEntry(inaccessible_dir, is_dir=True, is_file=False),
                            _FakeDirEntry(image_path, is_dir=False, is_file=True),
                        ]
                    )
                if path == inaccessible_dir:
                    raise PermissionError(13, "Access denied", path)
                raise AssertionError(f"Unexpected scandir path: {path}")

            with (
                patch("dt_image_search.index.index_worker.create_db_conn", return_value=_ConnContext(conn)),
                patch("dt_image_search.index.index_worker.update_folder_status") as update_folder_status_mock,
                patch("dt_image_search.index.index_worker.get_folder_by_path", return_value=None),
                patch("dt_image_search.index.index_worker.is_image_file", return_value=True),
                patch("dt_image_search.index.index_worker.insert_file") as insert_file_mock,
                patch("dt_image_search.index.index_worker.index_path_for_folder", return_value="index.faiss"),
                patch(
                    "dt_image_search.index.index_worker.build_index",
                    return_value=iter([{"files_processed": 1, "total_files": 1, "batch_result": True}]),
                ),
                patch("dt_image_search.index.index_worker.status_bar_messenger", status_bar_mock),
                patch("dt_image_search.index.index_worker.os.scandir", side_effect=_scandir),
            ):
                worker._run_impl()

            insert_file_mock.assert_called_once_with(conn, image_path, folder.id)
            self.assertEqual(
                [call.args[2] for call in update_folder_status_mock.call_args_list],
                [0, 1, 3],
            )
            status_bar_mock.show_status_message.emit.assert_any_call(f"Indexing partially failed: {folder.path}")


if __name__ == "__main__":
    unittest.main()
