def get_config(conn, key: str, default=None):
    """Read a config value from app_config table. Returns default if not found."""
    cursor = conn.execute("SELECT value FROM app_config WHERE key = ?", (key,))
    row = cursor.fetchone()
    return row[0] if row else default

def set_config(conn, key: str, value: str):
    """Write a config value to app_config table. Overwrites if exists."""
    conn.execute("INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))
    conn.commit()

import os
import sqlite3
import threading
from importlib.resources import files
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.tools.dts_perf import perffunc
from dt_image_search.bm_context import BMContext


def _folder_path_variants(folder_path: str) -> tuple[str, ...]:
    normalized_path = folder_path.replace('\\', '/')
    if normalized_path == "/":
        return (normalized_path,)
    trimmed_path = normalized_path.rstrip('/')
    return (trimmed_path, trimmed_path + '/')

def _sql_logger(statement):
    print("SQL:", statement)

db_init_lock = threading.Lock()


class _ManagedSQLiteConnection(sqlite3.Connection):
    def __exit__(self, exc_type, exc_value, traceback):
        try:
            return super().__exit__(exc_type, exc_value, traceback)
        finally:
            self.close()


def create_db_conn(ctx: BMContext) -> sqlite3.Connection:
    db_path = get_app_data_path(ctx) / "app_data.sqlite"
    conn = None
    with db_init_lock:
        if not db_path.exists():
            conn = sqlite3.connect(db_path, factory=_ManagedSQLiteConnection)
            schema_sql = files("dt_image_search.model").joinpath("db_schema.sql").read_text()
            conn.executescript(schema_sql)
    if conn is None:
        conn = sqlite3.connect(db_path, timeout=30, factory=_ManagedSQLiteConnection)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    from dt_image_search.mobile.mobile_pairing_store import ensure_mobile_pairing_schema
    ensure_mobile_pairing_schema(conn)
    if 'DB_LOGGING' in os.environ:
        conn.set_trace_callback(_sql_logger)  # Set the trace callback for logging SQL statements
    return conn

def get_folder_by_id(conn, folder_id: int) -> Folder:
    cursor = conn.execute("SELECT id, path, status, added_at FROM folders WHERE id = ?", (folder_id,))
    row = cursor.fetchone()
    if row:
        return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3])
    return None

def insert_folder(conn, folder_path: str) -> Folder:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR IGNORE INTO folders (path) VALUES (?)",
        (folder_path,)
    )
    conn.commit()
    # If no row was inserted, return None
    if cursor.rowcount == 0:
        return None
    cursor.execute("SELECT id, path, status, added_at FROM folders WHERE path = ?", (folder_path,))
    row = cursor.fetchone()
    return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3]) if row else None

def has_any_folder(conn) -> bool:
    cursor = conn.execute("SELECT 1 FROM folders LIMIT 1")
    return cursor.fetchone() is not None

def get_all_folders(conn):
    cursor = conn.execute("SELECT id, path, status, added_at FROM folders")
    return [Folder(id = row[0], path = row[1], status = row[2], added_at= row[3]) for row in cursor.fetchall()]  # Ensure the query is executed

def get_subfolders(conn, folder_path: str) -> list[Folder]:
    folder_path = folder_path.replace('\\', '/')
    if folder_path == "/":
        cursor = conn.execute(
            "SELECT id, path, status, added_at FROM folders WHERE path = '/' OR path LIKE '/%'"
        )
        return [Folder(id=row[0], path=row[1], status=row[2], added_at=row[3]) for row in cursor.fetchall()]

    normalized_prefix = folder_path.rstrip('/')
    with_trailing_slash = normalized_prefix + '/'
    cursor = conn.execute(
        """
        SELECT id, path, status, added_at
        FROM folders
        WHERE path = ? OR path = ? OR path LIKE ?
        """,
        (normalized_prefix, with_trailing_slash, with_trailing_slash + '%'),
    )
    return [Folder(id = row[0], path = row[1], status = row[2], added_at= row[3]) for row in cursor.fetchall()]  # Ensure the query is executed

def get_folder_by_path(conn, folder_path: str) -> Folder:
    folder_path_variants = _folder_path_variants(folder_path)
    placeholders = ", ".join("?" for _ in folder_path_variants)
    cursor = conn.execute(
        f"""
        SELECT id, path, status, added_at
        FROM folders
        WHERE path IN ({placeholders})
        ORDER BY LENGTH(path) ASC
        LIMIT 1
        """,
        folder_path_variants,
    )
    row = cursor.fetchone()
    if row:
        return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3])
    return None

def update_folder_status(conn, folder_id: int, status: int):
    conn.execute("UPDATE folders SET status = ? WHERE id = ?", (status, folder_id))
    conn.commit()

def is_folder_exists(conn, folder_path: str) -> bool:
    folder_path_variants = _folder_path_variants(folder_path)
    placeholders = ", ".join("?" for _ in folder_path_variants)
    cursor = conn.execute(f"SELECT 1 FROM folders WHERE path IN ({placeholders})", folder_path_variants)
    return cursor.fetchone() is not None

def match_parent_folder(conn, path: str) -> Folder:
    # Replace '\' with '/' for consistency
    path = path.replace('\\', '/')
    cursor = conn.execute("SELECT id, path, status, added_at FROM folders WHERE ? LIKE path || '%' ORDER BY LENGTH(path) DESC LIMIT 1", (path,))
    row = cursor.fetchone()
    if row:
        return Folder(id=row[0], path=row[1], status=row[2], added_at=row[3])
    return None

def delete_folders(conn, folder_paths: list):
    # Replace '\' with '/' for consistency
    normalized_paths = [path.replace('\\', '/') for path in folder_paths]
    folder_paths = []
    for path in normalized_paths:
        for variant in _folder_path_variants(path):
            if variant not in folder_paths:
                folder_paths.append(variant)
    if not folder_paths:
        return
    placeholders = ', '.join('?' for _ in folder_paths)

    folder_rows = conn.execute(
        f"SELECT id FROM folders WHERE path IN ({placeholders})",
        folder_paths,
    ).fetchall()
    folder_ids = [int(row["id"]) if isinstance(row, sqlite3.Row) else int(row[0]) for row in folder_rows]
    if folder_ids:
        from dt_image_search.mobile.mobile_pairing_store import delete_mobile_device_data_for_folder_ids
        delete_mobile_device_data_for_folder_ids(conn, folder_ids)

    conn.execute(f"DELETE FROM folders WHERE path IN ({placeholders})", folder_paths)
    conn.commit()

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
        # If the file already exists, we can set status = 0 if it was 2 otherwise do nothing
        conn.execute(
            "UPDATE files SET status = 0 WHERE path = ? and folder_id == ? and status == 2",
            (path, folder_id)
        )
    finally:
        conn.commit()

@perffunc
def get_file_by_path(conn, path: str) -> File:
    # Replace '\' with '/' for consistency
    path = path.replace('\\', '/')
    cursor = conn.execute("SELECT id, path, folder_id, clip_index, status FROM files WHERE path = ?", (path,))
    row = cursor.fetchone()
    if row:
        return File(id=row[0], path=row[1], folder_id=row[2], clip_index=row[3], status=row[4])
    return None

@perffunc
def get_direct_child_files(conn, subtree: str) -> list[File]:
    # Replace '\' with '/' for consistency
    subtree = subtree.replace('\\', '/')
    if not subtree.endswith('/'):
        subtree += '/'
    cursor = conn.execute("SELECT id, path, folder_id, clip_index, status FROM files WHERE path LIKE ? AND path NOT LIKE ?",
                          (subtree + '%', subtree + '%/%'))
    return [File(id=row[0], path=row[1], folder_id=row[2], clip_index=row[3], status=row[4]) for row in cursor.fetchall()]

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
def rename_file(conn, old_path: str, src_file: File, new_path: str, dest_folder: Folder) -> int:
    # Replace '\' with '/' for consistency
    old_path = old_path.replace('\\', '/')
    new_path = new_path.replace('\\', '/')

    # Remove the file with path = new_path because it's replaced on fs
    conn.execute(
        "DELETE FROM files WHERE path = ?",
        (new_path,)
    )
    # old_path may not exist. If so, we need to create a new file with new_path and dest_folder.id. If old_path exists, we need to update its path to new_path and folder_id to dest_folder.id
    conn.execute(
        "UPDATE files SET path = ?, folder_id = ? WHERE path = ?",
        (new_path, dest_folder.id, old_path)
    )
    conn.commit()
    # return number of rows updated
    return conn.total_changes

@perffunc
def rename_files_in_folder(conn, folder_path: str, src_file: File, new_folder_path: str, dest_folder: Folder) -> int:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    new_folder_path = new_folder_path.replace('\\', '/')
    if not folder_path.endswith('/'):
        folder_path += '/'
    if not new_folder_path.endswith('/'):
        new_folder_path += '/'
    cursor = conn.execute("SELECT id, path FROM files WHERE path LIKE ?", (folder_path + '%',))
    rows = cursor.fetchall()
    for row in rows:
        file_id = row[0]
        old_file_path = row[1]
        new_file_path = new_folder_path + old_file_path[len(folder_path):]
        conn.execute(
            "DELETE FROM files WHERE path = ?",
            (new_file_path,)
        )
        conn.execute(
            "UPDATE files SET path = ?, folder_id = ? WHERE id = ?",
            (new_file_path, dest_folder.id, file_id)
        )
    conn.commit()
    return len(rows)

@perffunc
def mark_files_deleted(conn, ids: list):
    if not ids:
        return
    placeholders = ', '.join('?' for _ in ids)
    conn.execute(
        f"UPDATE files SET status = 2 WHERE id IN ({placeholders})",
        ids
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

def get_pending_files_for_folder(conn, folder_id: int, offset: int = 0, limit: int = 100) -> list[File]:
    cursor = conn.execute(
        "SELECT id, path, clip_index, status FROM files WHERE folder_id = ? AND status = 0 ORDER BY id LIMIT ? OFFSET ?",
        (folder_id, limit, offset)
    ).fetchall()
    return [File(id=row[0], path=row[1], folder_id=folder_id, clip_index=row[2], status=row[3])
            for row in cursor]

def count_files_in_folder(conn, folder_id: int) -> int:
    cursor = conn.execute("SELECT COUNT(*) FROM files WHERE folder_id = ?", (folder_id,))
    row = cursor.fetchone()
    return row[0] if row else 0

def delete_files_by_folder_id(conn, folder_id: int):
    conn.execute("DELETE FROM files WHERE folder_id = ?", (folder_id,))
    conn.commit()

def delete_files_by_ids(conn, ids: list[int]):
    if not ids:
        return
    for i in range(0, len(ids), 20):  # Batch delete to avoid SQLite limits
        batch = ids[i:i+20]
        placeholders = ', '.join('?' for _ in batch)
        conn.execute(f"DELETE FROM files WHERE id IN ({placeholders})", batch)
        conn.commit()

def match_child_files(conn, folder_path: str) -> list[File]:
    # Replace '\' with '/' for consistency
    folder_path = folder_path.replace('\\', '/')
    if not folder_path.endswith('/'):
        folder_path += '/'
    cursor = conn.execute("SELECT id, path, folder_id, clip_index, status FROM files WHERE path LIKE ?", (folder_path + '%',))
    return [File(id=row[0], path=row[1], folder_id=row[2], clip_index=row[3], status=row[4]) for row in cursor.fetchall()]  # Ensure the query is executed
