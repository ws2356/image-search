# Unit tests for the thumbnail cache and media routes.
# Real PIL + real SQLite; only the heavy ML import chain is stubbed.
import hashlib
import os
import sys
import sqlite3
import tempfile
from unittest.mock import MagicMock

noop_decorator = lambda f: f

sys.modules['faiss'] = MagicMock()
sys.modules['open_clip'] = MagicMock()
sys.modules['torch'] = MagicMock()
sys.modules['torchvision'] = MagicMock()
sys.modules['torchvision.transforms'] = MagicMock()
sys.modules['hf_xet'] = MagicMock()
sys.modules['PySide6'] = MagicMock()
sys.modules['PySide6.QtCore'] = MagicMock()
sys.modules['PySide6.QtWidgets'] = MagicMock()
sys.modules['PySide6.QtGui'] = MagicMock()
sys.modules['requests'] = MagicMock()
sys.modules['psutil'] = MagicMock()
sys.modules['watchdog'] = MagicMock()
sys.modules['watchdog.observers'] = MagicMock()
sys.modules['watchdog.events'] = MagicMock()
sys.modules['opentelemetry'] = MagicMock()
sys.modules['opentelemetry.trace'] = MagicMock()
sys.modules['opentelemetry.sdk'] = MagicMock()
sys.modules['opentelemetry.sdk.trace'] = MagicMock()
sys.modules['opentelemetry.sdk.trace.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.trace_exporter'] = MagicMock()
sys.modules['opentelemetry.sdk.resources'] = MagicMock()
sys.modules['opentelemetry.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.metric_exporter'] = MagicMock()
sys.modules['opentelemetry._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http._log_exporter'] = MagicMock()
sys.modules['opentelemetry.instrumentation'] = MagicMock()
sys.modules['opentelemetry.context'] = MagicMock()
sys.modules['opentelemetry.context.contextvars_context'] = MagicMock()
sys.modules['pc_common.telemetry.telemetry_client'] = MagicMock()
mock_perf = MagicMock()
mock_perf.perffunc = noop_decorator
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf
sys.modules['pc_common.telemetry.telemetry_client'].with_trace = lambda _: noop_decorator

import unittest
from unittest.mock import MagicMock, patch
from importlib.resources import files

from fastapi.testclient import TestClient
from PIL import Image

from dt_image_search.index_server.app import create_app
from dt_image_search.index_server.media import ThumbnailCache, FileGoneError
from dt_image_search.model.dts_file import File

ROUTES = 'dt_image_search.index_server.routes'
TOKEN = "tok"
HEADERS = {"X-Auth-Token": TOKEN}


def _make_jpeg(path, size=(2000, 1000), color=(255, 0, 0)):
    img = Image.new("RGB", size, color)
    img.save(path, "JPEG")


class TestThumbnailCache(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.cache_dir = os.path.join(self._tmp.name, "thumb_cache")
        self.src = os.path.join(self._tmp.name, "cat.jpg")
        _make_jpeg(self.src)

    def tearDown(self):
        self._tmp.cleanup()

    def test_builds_then_serves_from_disk_without_redecoding(self):
        cache = ThumbnailCache(cache_dir=self.cache_dir, max_memory_items=8)
        f = File(id=1, path=self.src.replace('\\', '/'), folder_id=1)
        with patch('dt_image_search.index_server.media.open_pil_image', wraps=None) as mock_open:
            mock_open.side_effect = lambda p: Image.open(p)
            first = cache.get_or_build(f, size=300)
            second = cache.get_or_build(f, size=300)

        self.assertEqual(first, second)
        self.assertTrue(os.path.exists(first))
        self.assertTrue(first.endswith(f"{hashlib.sha1(f.path.encode()).hexdigest()}_300.jpg"))
        self.assertEqual(mock_open.call_count, 1)  # second call served from disk

        with Image.open(first) as thumb:
            self.assertEqual(thumb.format, "JPEG")
            self.assertLessEqual(max(thumb.size), 300)

    def test_missing_source_raises_file_gone(self):
        cache = ThumbnailCache(cache_dir=self.cache_dir)
        f = File(id=1, path="/no/such/file.jpg", folder_id=1)
        with self.assertRaises(FileGoneError):
            cache.get_or_build(f, size=300)

    def test_lru_eviction_keeps_disk_cache(self):
        cache = ThumbnailCache(cache_dir=self.cache_dir, max_memory_items=2)
        paths = []
        for i in range(3):
            src = os.path.join(self._tmp.name, f"img{i}.jpg")
            _make_jpeg(src, size=(100, 100), color=(i, 0, 0))
            f = File(id=i + 1, path=src.replace('\\', '/'), folder_id=1)
            paths.append(cache.get_or_build(f))

        self.assertEqual(len(cache._mem), 2)
        for p in paths:
            self.assertTrue(os.path.exists(p))  # disk cache survives eviction


class _SqliteFixture:
    def __enter__(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._db = os.path.join(self._tmp.name, "test.sqlite")
        conn = sqlite3.connect(self._db)
        conn.row_factory = sqlite3.Row
        conn.executescript(files("dt_image_search.model").joinpath("db_schema.sql").read_text())
        conn.commit()
        conn.close()
        return self

    def __exit__(self, *exc):
        self._tmp.cleanup()
        return False

    def connect(self):
        return sqlite3.connect(self._db, timeout=30)

    def client(self, cache_dir=None):
        from dt_image_search.index_server.media import ThumbnailCache as TC
        conn_cm = MagicMock()
        conn_cm.return_value.__enter__ = lambda s: self.connect()
        conn_cm.return_value.__exit__ = lambda s, *a: False
        with patch(f'{ROUTES}.create_db_conn', conn_cm):
            app = create_app(ctx=MagicMock(), token=TOKEN)
            if cache_dir is None:
                cache_dir = os.path.join(self._tmp.name, "thumb_cache")
            app.state.thumbnail_cache = TC(cache_dir=cache_dir)
            yield TestClient(app)


class TestMediaRoutes(unittest.TestCase):
    def _seed(self, db, src_path):
        conn = db.connect()
        cursor = conn.execute("INSERT INTO files (path, folder_id, status) VALUES (?, 1, 1)", (src_path,))
        conn.commit()
        file_id = cursor.lastrowid
        conn.close()
        return file_id

    def test_thumb_serves_jpeg(self):
        with _SqliteFixture() as db:
            src = os.path.join(db._tmp.name, "cat.jpg")
            _make_jpeg(src)
            file_id = self._seed(db, src)
            for client in db.client():
                resp = client.get(f"/thumb/{file_id}", headers=HEADERS)
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.headers["content-type"], "image/jpeg")

    def test_thumb_missing_id_is_404(self):
        with _SqliteFixture() as db:
            for client in db.client():
                resp = client.get("/thumb/9999", headers=HEADERS)
            self.assertEqual(resp.status_code, 404)

    def test_thumb_source_deleted_is_404(self):
        with _SqliteFixture() as db:
            file_id = self._seed(db, "/gone/from/disk.jpg")
            for client in db.client():
                resp = client.get(f"/thumb/{file_id}", headers=HEADERS)
            self.assertEqual(resp.status_code, 404)

    def test_file_serves_original_with_content_type(self):
        with _SqliteFixture() as db:
            src = os.path.join(db._tmp.name, "pic.png")
            Image.new("RGB", (50, 50), (0, 255, 0)).save(src, "PNG")
            file_id = self._seed(db, src)
            for client in db.client():
                resp = client.get(f"/file/{file_id}", headers=HEADERS)
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.headers["content-type"], "image/png")

    def test_file_missing_id_is_404(self):
        with _SqliteFixture() as db:
            for client in db.client():
                resp = client.get("/file/9999", headers=HEADERS)
            self.assertEqual(resp.status_code, 404)


if __name__ == "__main__":
    unittest.main()
