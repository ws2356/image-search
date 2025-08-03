import logging
import sqlite3
import threading
from PySide6.QtCore import QStandardPaths, QDir
from pathlib import Path
from importlib.resources import files
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.tools.dts_perf import perffunc
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dt_is_debug import is_debug

def _sql_logger(statement):
    print("SQL:", statement)

db_init_lock = threading.Lock()
def create_db_conn():
    db_path = get_app_data_path() / "app_data.sqlite"
    conn = None
    with db_init_lock:
        if not db_path.exists():
            conn = sqlite3.connect(db_path)
            schema_sql = files("dt_image_search.model").joinpath("db_schema.sql").read_text()
            log("info", message=f"Db path: {db_path}")
            conn.executescript(schema_sql)
    if conn is None:
        conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    if is_debug():
        conn.set_trace_callback(_sql_logger)  # Set the trace callback for logging SQL statements
        print(f"db path: {db_path}")
    return conn

def insert_folder(conn, folder_path: str) -> Folder:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR IGNORE INTO folders (path) VALUES (?)",
        (folder_path,)
    )
    conn.commit()
    cursor.execute("SELECT id, path, status, added_at FROM folders WHERE path = ?", (folder_path,))
    row = cursor.fetchone()
    return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3]) if row else None

def get_all_folders(conn):
    cursor = conn.execute("SELECT id, path, status, added_at FROM folders")
    return [Folder(id = row[0], path = row[1], status = row[2], added_at= row[3]) for row in cursor.fetchall()]  # Ensure the query is executed

def get_folder_by_path(conn, folder_path: str) -> Folder:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    cursor = conn.execute("SELECT id, path, status, added_at FROM folders WHERE path = ?", (folder_path,))
    row = cursor.fetchone()
    if row:
        return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3])
    return None

def update_folder_status(conn, folder_id: int, status: int):
    conn.execute("UPDATE folders SET status = ? WHERE id = ?", (status, folder_id))
    conn.commit()

def is_folder_exists(conn, folder_path: str) -> bool:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    cursor = conn.execute("SELECT 1 FROM folders WHERE path = ?", (folder_path,))
    return cursor.fetchone() is not None

def match_parent_folder(conn, path: str) -> str:
    # Replace '\' with '/' for consistency
    path = path.replace('\\', '/')
    cursor = conn.execute("SELECT path FROM folders WHERE ? LIKE path || '%'", (path,))
    row = cursor.fetchone()
    if row:
        return row[0]
    return None

def delete_folders(conn, folder_paths: list):
    # Replace '\' with '/' for consistency
    folder_paths = [path.replace('\\', '/') for path in folder_paths]
    if not folder_paths:
        return
    placeholders = ', '.join('?' for _ in folder_paths)
    conn.execute(f"DELETE FROM folders WHERE path IN ({placeholders})", folder_paths)
    conn.commit()

def match_child_folders(conn, path: str) -> list:
    # Replace '\' with '/' for consistency
    path = path.replace('\\', '/')
    cursor = conn.execute("SELECT path FROM folders WHERE ? LIKE '%' || path", (path,))
    return [row[0] for row in cursor.fetchall()]

@perffunc
def insert_file(conn, path: str, folder_id: int):
    # Replace '\' with '/' for consistency
    path = path.replace('\\', '/')
    # Catch the case uniq constraint violation
    try:
        conn.execute(
            "INSERT INTO files (path, folder_id) VALUES (?, ?)",
            (path, folder_id)
        )
    except sqlite3.IntegrityError:
        # If the file already exists, we can update it instead
        pass
    finally:
        conn.commit()

@perffunc
def update_file(conn, file_id: int, path: str = None, folder_id: int = None, clip_index=None, status=None):
    updates = []
    params = []
    
    if path is not None:
        # Replace '\' with '/' for consistency
        path = path.replace('\\', '/')
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
def get_files_by_clip_indices(conn, folder_id, clip_indices: list):
    if not clip_indices:
        return []
    placeholders = ', '.join('?' for _ in clip_indices)
    # cursor = conn.execute(f"SELECT path, clip_index FROM files WHERE clip_index IN ({placeholders}) AND status = 1", clip_indices)
    cursor = conn.execute(
        f"SELECT path, clip_index FROM files WHERE folder_id = ? AND clip_index IN ({placeholders}) AND status = 1",
        (folder_id, *clip_indices)
    )
    path_by_clip_index = {row[1]: row[0] for row in cursor.fetchall()}
    return [path_by_clip_index.get(clip_index) for clip_index in clip_indices]

def get_pending_files_for_folder(conn, folder_id: int):
    cursor = conn.execute(
        "SELECT id, path, clip_index, status FROM files WHERE folder_id = ? AND status = 0",
        (folder_id,)
    ).fetchall()
    return [File(id=row[0], path=row[1], folder_id=folder_id, clip_index=row[2], status=row[3])
            for row in cursor]

def delete_files_by_folder_id(conn, folder_id: int):
    conn.execute("DELETE FROM files WHERE folder_id = ?", (folder_id,))
    conn.commit()