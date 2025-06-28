import logging
import sqlite3
from PySide6.QtCore import QStandardPaths, QDir
from pathlib import Path
from importlib.resources import files
from dt_image_search.model.folder import Folder
from dt_image_search.model.file import File
from dt_image_search.model.fs import get_app_data_path
from dt_image_search.tools.perf import perffunc

def _sql_logger(statement):
    print("SQL:", statement)

def create_db_conn():
    db_path = get_app_data_path() / "app_data.sqlite"
    logging.info(f"Db path: {db_path}")
    db_exists = db_path.exists()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.set_trace_callback(_sql_logger)  # Set the trace callback for logging SQL statements
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
    return [Folder(id = row[0], path = row[1]) for row in cursor.fetchall()]  # Ensure the query is executed

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

@perffunc
def insert_file(conn, path: str, folder_id: int, clip_index=None, status=0):
    conn.execute(
        "INSERT INTO files (path, folder_id, clip_index, status) VALUES (?, ?, ?, ?)",
        (path, folder_id, clip_index, status)
    )
    conn.commit()

@perffunc
def update_file(conn, file_id: int, path: str = None, folder_id: int = None, clip_index=None, status=None):
    updates = []
    params = []
    
    if path is not None:
        updates.append("path = ?")
        params.append(path)
    if folder_id is not None:
        updates.append("folder_id = ?")
        params.append(folder_id)
    if clip_index is not None:
        updates.append("clip_index = ?")
        params.append(clip_index)
    if status is not None:
        updates.append("status = ?")
        params.append(status)

    if not updates:
        return  # No updates to perform

    params.append(file_id)  # Add file_id to the end of the parameters
    conn.execute(
        f"UPDATE files SET {', '.join(updates)} WHERE id = ?",
        params
    )
    conn.commit()

@perffunc
def update_files(conn, ids: list, clip_indices: list, statuses: list):
    if not ids or not clip_indices or not statuses:
        return
    if len(ids) != len(clip_indices) or len(ids) != len(statuses):
        raise ValueError("Length of ids, clip_indices and statuses must match")
    
    placeholders = ', '.join('?' for _ in ids)
    conn.execute(
        f"UPDATE files SET clip_index = ?, status = ? WHERE id IN ({placeholders})",
        [(clip_index, status) + (id,) for id, clip_index, status in zip(ids, clip_indices, statuses)]
    )
    conn.commit()

@perffunc
def get_files_by_clip_indices(conn, clip_indices: list):
    if not clip_indices:
        return []
    placeholders = ', '.join('?' for _ in clip_indices)
    cursor = conn.execute(f"SELECT path, clip_index FROM files WHERE clip_index IN ({placeholders}) AND status = 1", clip_indices)
    path_by_clip_index = {row[1]: row[0] for row in cursor.fetchall()}
    return [path_by_clip_index.get(clip_index) for clip_index in clip_indices]

def get_pending_files_for_folder(conn, folder_id: int):
    cursor = conn.execute(
        "SELECT id, path, clip_index, status FROM files WHERE folder_id = ? AND status = 0",
        (folder_id,)
    ).fetchall()
    return [File(id=row[0], path=row[1], folder_id=folder_id, clip_index=row[2], status=row[3])
            for row in cursor]
