# Unit tests for dts_db.get_file_by_id.
import sqlite3
import unittest
from importlib.resources import files

from dt_image_search.model.dts_db import get_file_by_id


def _conn_with_file():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(files("dt_image_search.model").joinpath("db_schema.sql").read_text())
    cursor = conn.execute("INSERT INTO files (path, folder_id, clip_index, status) VALUES (?, ?, ?, ?)",
                          ("photos/cat.jpg", "1", 7, 1))
    conn.commit()
    return conn, cursor.lastrowid


class TestGetFileById(unittest.TestCase):
    def test_returns_file_when_row_exists(self):
        conn, file_id = _conn_with_file()
        f = get_file_by_id(conn, file_id)
        self.assertEqual(f.id, file_id)
        self.assertEqual(f.path, "photos/cat.jpg")
        self.assertEqual(f.folder_id, 1)
        self.assertEqual(f.clip_index, 7)
        self.assertEqual(f.status, 1)
        conn.close()

    def test_returns_none_when_missing(self):
        conn, _ = _conn_with_file()
        self.assertIsNone(get_file_by_id(conn, 9999))
        conn.close()


if __name__ == "__main__":
    unittest.main()
