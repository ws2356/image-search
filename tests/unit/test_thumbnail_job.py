import os
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image
from PySide6.QtCore import QSize

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.browse.thumbnail_job import ThumbnailJob, ThumbnailJobSignals


class TestThumbnailJob(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

    def test_thumbnail_job_preserves_device_pixel_ratio(self):
        image_path = Path(self._temp_dir.name) / "sample.jpg"
        Image.new("RGB", (1200, 900), color=(10, 20, 30)).save(image_path)

        results: list[tuple[str, object]] = []
        signals = ThumbnailJobSignals()
        signals.finished.connect(lambda path, image: results.append((path, image)))

        ThumbnailJob(
            image_path.as_posix(),
            QSize(300, 300),
            2.0,
            signals,
        ).run()

        self.assertEqual(len(results), 1)
        returned_path, image = results[0]
        self.assertEqual(returned_path, image_path.as_posix())
        self.assertFalse(image.isNull())
        self.assertEqual(image.devicePixelRatio(), 2.0)
        self.assertLessEqual(image.width(), 300)
        self.assertLessEqual(image.height(), 300)


if __name__ == "__main__":
    unittest.main()
