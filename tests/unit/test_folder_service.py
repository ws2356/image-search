# Unit tests for the Qt-free folder service (register/watch/unwatch/reindex).
# Real SQLite (temp file) for DB behavior; dts_index / index_worker / bm_fs_monitor
# are patched at the service boundary. Heavy deps stubbed like test_dts_index.py.
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

from dt_image_search.browse import folder_service
from dt_image_search.model.dts_db import get_all_folders

SERVICE = 'dt_image_search.browse.folder_service'


class _SqliteFixture:
    """Real temp-file SQLite with the app schema, closed on each create_db_conn()."""

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

    def status_of(self, path):
        conn = self.connect()
        row = conn.execute("SELECT status FROM folders WHERE path = ?", (path,)).fetchone()
        conn.close()
        return row[0] if row else None


def _db_patch(fixture):
    conn_cm = MagicMock()
    conn_cm.return_value.__enter__ = lambda s: fixture.connect()
    conn_cm.return_value.__exit__ = lambda s, *a: False
    return patch(f'{SERVICE}.create_db_conn', conn_cm)


class TestFolderService(unittest.TestCase):
    def setUp(self):
        self.ctx = MagicMock()
        self.fs_add = MagicMock()
        self.fs_remove = MagicMock()
        self.index_worker = MagicMock()
        self.delete_folder = MagicMock()
        self.patches = [
            patch(f'{SERVICE}.watch_folder', self.fs_add),
            patch(f'{SERVICE}.unwatch_folder', self.fs_remove),
            patch(f'{SERVICE}.add_index_worker', self.index_worker),
            patch(f'{SERVICE}.delete_folder', self.delete_folder),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()

    def test_add_new_folder_registers_watches_and_enqueues_index(self):
        with _SqliteFixture() as db:
            with _db_patch(db):
                new_dir = os.path.join(db._tmp.name, "photos")

                folder, created = folder_service.register_folder(self.ctx, new_dir)

                self.assertTrue(created)
                self.assertIsNotNone(folder)
                self.assertEqual(folder.status, 0)
                self.assertEqual(folder.path, new_dir.replace('\\', '/') + '/')

                folder_service.watch_and_index(self.ctx, folder)

                self.fs_add.assert_called_once_with(folder.path)
                self.index_worker.assert_called_once_with(ctx=self.ctx, folder=folder)

    def test_add_existing_indexed_folder_is_idempotent(self):
        with _SqliteFixture() as db:
            with _db_patch(db):
                existing = os.path.join(db._tmp.name, "photos") + "/"
                conn = db.connect()
                conn.execute("INSERT INTO folders (path, status) VALUES (?, 2)", (existing,))
                conn.commit()
                conn.close()

                folder, created = folder_service.register_folder(self.ctx, existing)

                self.assertFalse(created)
                self.assertEqual(folder.status, 2)
                self.fs_add.assert_not_called()
                self.index_worker.assert_not_called()
                # no duplicate row
                conn = db.connect()
                count = conn.execute("SELECT COUNT(*) FROM folders").fetchone()[0]
                conn.close()
                self.assertEqual(count, 1)

    def test_watch_and_index_skips_worker_for_indexed_folder(self):
        with _SqliteFixture() as db:
            with _db_patch(db):
                path = os.path.join(db._tmp.name, "photos") + "/"
                conn = db.connect()
                conn.execute("INSERT INTO folders (path, status) VALUES (?, 2)", (path,))
                conn.commit()
                conn.close()

                folder, _ = folder_service.register_folder(self.ctx, path)

                folder_service.watch_and_index(self.ctx, folder)

                self.fs_add.assert_called_once_with(path)  # watch even when indexed
                self.index_worker.assert_not_called()  # but never re-enqueue

    def test_add_child_of_registered_folder_returns_parent_without_side_effects(self):
        with _SqliteFixture() as db:
            with _db_patch(db):
                parent = os.path.join(db._tmp.name, "photos") + "/"
                child = parent + "subdir/"
                conn = db.connect()
                conn.execute("INSERT INTO folders (path, status) VALUES (?, 2)", (parent,))
                conn.commit()
                conn.close()

                folder, created = folder_service.register_folder(self.ctx, child)

                self.assertFalse(created)
                self.assertEqual(folder.path, parent)
                self.fs_add.assert_not_called()
                self.index_worker.assert_not_called()
                conn = db.connect()
                rows = get_all_folders(conn)
                conn.close()
                self.assertEqual(len(rows), 1)  # child must not be inserted

    def test_remove_folder_unwatches_publishes_and_deletes(self):
        events = []
        with _SqliteFixture() as db:
            with _db_patch(db), patch(f'{SERVICE}.default_bus') as mock_bus:
                path = os.path.join(db._tmp.name, "photos") + "/"

                folder_service.remove_folder(self.ctx, path)

                self.fs_remove.assert_called_once_with(path)
                self.delete_folder.assert_called_once_with(ctx=self.ctx, folder_path=path)
                mock_bus.publish.assert_called_once_with("folder_deleted_from_ui", folder_path=path)
                self.assertEqual(events, [])

    def test_reindex_folder_resets_status_and_enqueues(self):
        with _SqliteFixture() as db:
            with _db_patch(db):
                path = os.path.join(db._tmp.name, "photos") + "/"
                conn = db.connect()
                conn.execute("INSERT INTO folders (path, status) VALUES (?, 2)", (path,))
                conn.commit()
                conn.close()

                folder, _ = folder_service.register_folder(self.ctx, path)

                folder_service.reindex_folder(self.ctx, folder)

                self.assertEqual(db.status_of(path), 0)
                self.index_worker.assert_called_once_with(ctx=self.ctx, folder=folder)


if __name__ == '__main__':
    unittest.main()
