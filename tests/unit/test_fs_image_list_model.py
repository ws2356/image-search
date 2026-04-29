import os
import sys
import tempfile
import unittest
from pathlib import Path

from PySide6.QtCore import QDeadlineTimer, Qt
from PySide6.QtWidgets import QApplication

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.browse.fs_image_list_model import FSImageListModel


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
_APP = QApplication.instance() or QApplication([])


class TestFSImageListModel(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

    def test_load_images_from_folder_populates_images_off_thread(self):
        folder = Path(self._temp_dir.name)
        (folder / "a.jpg").write_bytes(b"a")
        (folder / "b.png").write_bytes(b"b")
        (folder / "ignore.txt").write_text("x", encoding="utf-8")

        model = FSImageListModel()
        model.load_images_from_folder(folder.as_posix())

        self._wait_for(lambda: model.rowCount() == 2)

        self.assertEqual(
            [model.data(model.index(row, 0), Qt.UserRole) for row in range(model.rowCount())],
            [
                (folder / "a.jpg").as_posix(),
                (folder / "b.png").as_posix(),
            ],
        )

    def test_latest_folder_request_wins(self):
        folder_a = Path(self._temp_dir.name) / "folder-a"
        folder_b = Path(self._temp_dir.name) / "folder-b"
        folder_a.mkdir()
        folder_b.mkdir()
        (folder_a / "a.jpg").write_bytes(b"a")
        (folder_b / "b.jpg").write_bytes(b"b")

        model = FSImageListModel()
        model.load_images_from_folder(folder_a.as_posix())
        model.load_images_from_folder(folder_b.as_posix())

        self._wait_for(lambda: model.rowCount() == 1)

        self.assertEqual(
            model.data(model.index(0, 0), Qt.UserRole),
            (folder_b / "b.jpg").as_posix(),
        )

    def test_load_images_prunes_thumbnail_cache_for_non_visible_items(self):
        model = FSImageListModel()
        keep_path = (Path(self._temp_dir.name) / "keep.jpg").as_posix()
        drop_path = (Path(self._temp_dir.name) / "drop.jpg").as_posix()
        model.thumbnail_cache = {
            keep_path: object(),
            drop_path: object(),
        }
        model.loading_paths = {keep_path, drop_path}

        model.load_images([(keep_path, 0)])

        self.assertEqual(set(model.thumbnail_cache.keys()), {keep_path})
        self.assertEqual(model.loading_paths, {keep_path})

    def _wait_for(self, predicate, timeout_ms: int = 3000) -> None:
        deadline = QDeadlineTimer(timeout_ms)
        while not predicate():
            if deadline.hasExpired():
                self.fail("Timed out waiting for FSImageListModel background load")
            _APP.processEvents()


if __name__ == "__main__":
    unittest.main()
