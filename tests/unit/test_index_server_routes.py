# Unit tests for index server routes (folder/search/browse/reindex).
# Real SQLite temp-file DB; service functions patched at the routes module.
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
sys.modules['PIL'] = MagicMock()
sys.modules['PIL.Image'] = MagicMock()
sys.modules['PIL.ImageFile'] = MagicMock()
sys.modules['pc_common.telemetry.telemetry_client'] = MagicMock()
mock_perf = MagicMock()
mock_perf.perffunc = noop_decorator
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf
sys.modules['pc_common.telemetry.telemetry_client'].with_trace = lambda _: noop_decorator

import unittest
from unittest.mock import MagicMock, patch
from importlib.resources import files

from fastapi.testclient import TestClient

from dt_image_search.index_server.app import create_app
from dt_image_search.model.dts_folder import Folder

ROUTES = 'dt_image_search.index_server.routes'
TOKEN = "tok"

HEADERS = {"X-Auth-Token": TOKEN}


class _SqliteFixture:
    def __init__(self):
        self._conn = None

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

    def client(self):
        conn_cm = MagicMock()
        conn_cm.return_value.__enter__ = lambda s: self.connect()
        conn_cm.return_value.__exit__ = lambda s, *a: False
        with patch(f'{ROUTES}.create_db_conn', conn_cm):
            app = create_app(ctx=MagicMock(), token=TOKEN)
            yield TestClient(app)


class TestFolderRoutes(unittest.TestCase):
    def test_list_folders_empty(self):
        with _SqliteFixture() as db:
            for client in db.client():
                resp = client.get("/folders", headers=HEADERS)
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json(), {"folders": []})

    def test_list_folders_serializes_id_as_string(self):
        db = _SqliteFixture()
        with db:
            conn = db.connect()
            conn.execute("INSERT INTO folders (path, status, added_at) VALUES ('/p/', 1, '2026-01-01T00:00:00')")
            conn.commit()
            conn.close()
            for client in db.client():
                resp = client.get("/folders", headers=HEADERS)
                folder = resp.json()["folders"][0]
                self.assertEqual(folder["id"], str(folder["id"]))
                self.assertEqual(folder["path"], "/p/")
                self.assertEqual(folder["status"], 1)
                self.assertEqual(folder["added_at"], "2026-01-01T00:00:00")

    def test_add_folder_new_is_201_and_watches(self):
        db = _SqliteFixture()
        with db:
            registered = Folder(id=5, path="/new/", status=0, added_at="2026-01-01T00:00:00")
            with patch(f'{ROUTES}.register_folder', return_value=(registered, True)) as mock_reg, \
                 patch(f'{ROUTES}.watch_and_index') as mock_watch, \
                 patch(f'{ROUTES}.Path.is_dir', return_value=True):
                for client in db.client():
                    resp = client.post("/folders", json={"path": "/new"}, headers=HEADERS)
                self.assertEqual(resp.status_code, 201)
                self.assertEqual(resp.json()["id"], "5")
                mock_reg.assert_called_once()
                mock_watch.assert_called_once()

    def test_add_folder_existing_is_200_no_rewatch(self):
        db = _SqliteFixture()
        with db:
            existing = Folder(id=5, path="/p/", status=2, added_at="2026-01-01T00:00:00")
            with patch(f'{ROUTES}.register_folder', return_value=(existing, False)), \
                 patch(f'{ROUTES}.watch_and_index') as mock_watch, \
                 patch(f'{ROUTES}.Path.is_dir', return_value=True):
                for client in db.client():
                    resp = client.post("/folders", json={"path": "/p"}, headers=HEADERS)
                self.assertEqual(resp.status_code, 200)
                mock_watch.assert_not_called()

    def test_add_folder_child_hits_parent_200(self):
        db = _SqliteFixture()
        with db:
            parent = Folder(id=5, path="/p/", status=2, added_at="2026-01-01T00:00:00")
            with patch(f'{ROUTES}.register_folder', return_value=(parent, False)), \
                 patch(f'{ROUTES}.watch_and_index') as mock_watch, \
                 patch(f'{ROUTES}.Path.is_dir', return_value=True):
                for client in db.client():
                    resp = client.post("/folders", json={"path": "/p/sub"}, headers=HEADERS)
                self.assertEqual(resp.status_code, 200)
                self.assertEqual(resp.json()["path"], "/p/")
                mock_watch.assert_not_called()

    def test_add_folder_not_a_directory_is_400(self):
        db = _SqliteFixture()
        with db:
            for client in db.client():
                resp = client.post("/folders", json={"path": "/definitely/not/here"}, headers=HEADERS)
            self.assertEqual(resp.status_code, 400)

    def test_delete_folder_missing_is_404(self):
        db = _SqliteFixture()
        with db:
            for client in db.client():
                resp = client.delete("/folders/123", headers=HEADERS)
            self.assertEqual(resp.status_code, 404)

    def test_delete_folder_calls_service(self):
        db = _SqliteFixture()
        with db:
            conn = db.connect()
            conn.execute("INSERT INTO folders (path, status) VALUES ('/p/', 0)")
            conn.commit()
            folder_id = conn.execute("SELECT id FROM folders WHERE path = '/p/'").fetchone()[0]
            conn.close()
            with patch(f'{ROUTES}.remove_folder') as mock_remove:
                for client in db.client():
                    resp = client.delete(f"/folders/{folder_id}", headers=HEADERS)
                self.assertEqual(resp.status_code, 204)
                self.assertEqual(mock_remove.call_count, 1)
                self.assertEqual(mock_remove.call_args.args[1], "/p/")

    def test_reindex_folder(self):
        db = _SqliteFixture()
        with db:
            conn = db.connect()
            conn.execute("INSERT INTO folders (path, status) VALUES ('/p/', 0)")
            conn.commit()
            folder_id = conn.execute("SELECT id FROM folders WHERE path = '/p/'").fetchone()[0]
            conn.close()
            with patch(f'{ROUTES}.reindex_folder') as mock_reindex:
                for client in db.client():
                    resp = client.post(f"/folders/{folder_id}/reindex", headers=HEADERS)
                self.assertEqual(resp.status_code, 202)
                self.assertEqual(mock_reindex.call_count, 1)

    def test_reindex_indexed_folder_is_200(self):
        db = _SqliteFixture()
        with db:
            conn = db.connect()
            conn.execute("INSERT INTO folders (path, status) VALUES ('/p/', 2)")
            conn.commit()
            folder_id = conn.execute("SELECT id FROM folders WHERE path = '/p/'").fetchone()[0]
            conn.close()
            with patch(f'{ROUTES}.reindex_folder') as mock_reindex:
                for client in db.client():
                    resp = client.post(f"/folders/{folder_id}/reindex", headers=HEADERS)
                self.assertEqual(resp.status_code, 200)
                mock_reindex.assert_not_called()

    def test_reindex_missing_is_404(self):
        db = _SqliteFixture()
        with db:
            for client in db.client():
                resp = client.post("/folders/999/reindex", headers=HEADERS)
            self.assertEqual(resp.status_code, 404)


class TestSearchRoute(unittest.TestCase):
    def test_search_returns_merged_results(self):
        db = _SqliteFixture()
        with db:
            fake_file = MagicMock(id=11, path="photos/cat.jpg", folder_id=5)
            with patch(f'{ROUTES}.search_folders', return_value=[(fake_file, 0.87)]) as mock_search:
                for client in db.client():
                    resp = client.get("/search", params={"q": "cat"}, headers=HEADERS)
                self.assertEqual(resp.status_code, 200)
                self.assertEqual(resp.json(), {"results": [{"id": "11", "path": "photos/cat.jpg", "folder_id": "5", "score": 0.87}]})
                mock_search.assert_called_once()

    def test_search_model_not_ready_is_503(self):
        from dt_image_search.search.search_service import ModelNotReadyError
        db = _SqliteFixture()
        with db:
            with patch(f'{ROUTES}.search_folders', side_effect=ModelNotReadyError('loading')):
                for client in db.client():
                    resp = client.get("/search", params={"q": "cat"}, headers=HEADERS)
                self.assertEqual(resp.status_code, 503)
                self.assertEqual(resp.json()["detail"]["model_state"], "loading")

    def test_search_empty_query_is_422(self):
        db = _SqliteFixture()
        with db:
            for client in db.client():
                resp = client.get("/search", params={"q": ""}, headers=HEADERS)
            self.assertEqual(resp.status_code, 422)


class TestBrowseRoute(unittest.TestCase):
    def _seed(self, db):
        conn = db.connect()
        conn.execute("INSERT INTO folders (path, status) VALUES ('/p/', 2)")
        folder_id = conn.execute("SELECT id FROM folders WHERE path = '/p/'").fetchone()[0]
        conn.execute("INSERT INTO folders (path, status) VALUES ('/p/sub/', 2)")
        conn.execute("INSERT INTO files (path, folder_id, status) VALUES ('/p/a.jpg', ?, 1)", (folder_id,))
        conn.execute("INSERT INTO files (path, folder_id, status) VALUES ('/p/a.jpg/', ?, 1)", (folder_id,))
        conn.execute("INSERT INTO files (path, folder_id, status) VALUES ('/p/sub/deep.jpg', ?, 1)", (folder_id,))
        conn.commit()
        conn.close()
        return folder_id

    def test_browse_returns_subfolders_and_direct_image_files(self):
        db = _SqliteFixture()
        with db:
            folder_id = self._seed(db)
            for client in db.client():
                resp = client.get("/browse", params={"folder_id": folder_id}, headers=HEADERS)
            self.assertEqual(resp.status_code, 200)
            body = resp.json()
            self.assertEqual(body["folder"]["path"], "/p/")
            self.assertEqual([f["path"] for f in body["subfolders"]], ["/p/sub/"])
            self.assertEqual([f["path"] for f in body["files"]], ["/p/a.jpg"])

    def test_browse_missing_folder_is_404(self):
        db = _SqliteFixture()
        with db:
            for client in db.client():
                resp = client.get("/browse", params={"folder_id": 999}, headers=HEADERS)
            self.assertEqual(resp.status_code, 404)


if __name__ == "__main__":
    unittest.main()
