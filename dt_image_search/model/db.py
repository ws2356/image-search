import logging
import sqlite3
from PySide6.QtCore import QStandardPaths, QDir
from pathlib import Path
from importlib.resources import files

def _get_app_data_path() -> Path:
    APP_NAME = "DTImageSearch"
    base_path = QStandardPaths.writableLocation(QStandardPaths.AppDataLocation)
    data_path = Path(base_path) / APP_NAME
    data_path.mkdir(parents=True, exist_ok=True)
    return data_path

def create_db_conn():
    db_path = _get_app_data_path() / "app_data.sqlite"
    logging.info(f"Db path: {db_path}")
    db_exists = db_path.exists()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    schema_sql = files("dt_image_search.model").joinpath("db_schema.sql").read_text()
    if not db_exists:
        conn.executescript(schema_sql)
    return conn

def insert_folder(conn, folder_path: str) -> int:
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR IGNORE INTO folders (path) VALUES (?)",
        (folder_path,)
    )
    conn.commit()
    cursor.execute("SELECT id FROM folders WHERE path = ?", (folder_path,))
    return cursor.fetchone()[0]

def get_all_folders(conn):
    cursor = conn.execute("SELECT id, path FROM folders")
    return [row[1] for row in cursor.fetchall()]  # Ensure the query is executed

def is_folder_exists(conn, folder_path: str) -> bool:
    cursor = conn.execute("SELECT 1 FROM folders WHERE path = ?", (folder_path,))
    return cursor.fetchone() is not None

def match_parent_folder(conn, path: str) -> str:
    cursor = conn.execute("SELECT path FROM folders WHERE ? LIKE path || '%'", (path,))
    return cursor.fetchone()[0] if cursor.fetchone() else None

def remove_folders(conn, folder_paths: list):
    if not folder_paths:
        return
    placeholders = ', '.join('?' for _ in folder_paths)
    conn.execute(f"DELETE FROM folders WHERE path IN ({placeholders})", folder_paths)
    conn.commit()

def match_child_folders(conn, path: str) -> list:
    cursor = conn.execute("SELECT path FROM folders WHERE ? LIKE '%' || path", (path,))
    return [row[0] for row in cursor.fetchall()]

def insert_file(conn, path: str, folder_id: int, clip_index=None, status="normal"):
    conn.execute(
        "INSERT INTO files (path, folder_id, clip_index, status) VALUES (?, ?, ?, ?)",
        (path, folder_id, clip_index, status)
    )
    conn.commit()

def get_files_for_folder(conn, folder_id: int):
    return conn.execute(
        "SELECT path FROM files WHERE folder_id = ? AND status = 'normal'",
        (folder_id,)
    ).fetchall()
