import os
from pathlib import Path
import tempfile
import unittest
import uuid

from dt_image_search.bm_context import BMContext
from dt_image_search.model.dts_fs import get_app_private_name
from dt_image_search.model.dts_db import (
    create_db_conn,
    delete_folders,
    get_folder_by_path,
    get_subfolders,
    insert_folder,
)
from dt_image_search.tools.dts_util import normalized_folder_path


class TestDtsDbFolderPathVariants(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"dts-db-path-variants-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{get_app_private_name()}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

    def test_get_subfolders_includes_root_when_stored_without_trailing_slash(self):
        root_folder = (Path(self._temp_dir.name) / "Mobile Backup").resolve()
        child_folder = (root_folder / "nested").resolve()
        child_folder.mkdir(parents=True, exist_ok=True)

        with create_db_conn() as conn:
            insert_folder(conn, root_folder.as_posix())
            insert_folder(conn, child_folder.as_posix())

            folders = get_subfolders(conn, normalized_folder_path(root_folder.as_posix()))

        folder_paths = {folder.path for folder in folders}
        self.assertIn(root_folder.as_posix(), folder_paths)
        self.assertIn(child_folder.as_posix(), folder_paths)

    def test_delete_folders_removes_rows_with_and_without_trailing_slash(self):
        root_folder = (Path(self._temp_dir.name) / "Mobile Backup Delete").resolve()
        root_folder.mkdir(parents=True, exist_ok=True)

        with create_db_conn() as conn:
            insert_folder(conn, root_folder.as_posix())

            delete_folders(conn, [normalized_folder_path(root_folder.as_posix())])

            self.assertIsNone(get_folder_by_path(conn, root_folder.as_posix()))


if __name__ == "__main__":
    unittest.main()
