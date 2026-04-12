from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import base64
import hashlib
from pathlib import Path
import re
import sqlite3
import uuid

from dt_image_search.model.dts_db import get_config, insert_folder, set_config

MOBILE_PAIRING_DESKTOP_DEVICE_ID_KEY = "mobile_pairing_desktop_device_id"
MOBILE_TRANSFER_STATE_PAIRED = "paired"
MOBILE_TRANSFER_STATE_TRANSFERRING = "transferring"
MOBILE_TRANSFER_STATE_COMPLETED = "transfer_completed"
MOBILE_TRANSFER_STATE_FAILED = "failed"
MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING = "transferring"
MOBILE_BACKUP_SESSION_STATUS_COMPLETED = "completed"
MOBILE_BACKUP_SESSION_STATUS_FAILED = "failed"

_MOBILE_PAIRING_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS mobile_devices (
    device_uuid TEXT PRIMARY KEY,
    platform TEXT NOT NULL,
    device_name TEXT NOT NULL,
    trust_key_b64 TEXT NOT NULL,
    paired_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mobile_folders (
    folder_id INTEGER PRIMARY KEY REFERENCES folders(id),
    device_uuid TEXT UNIQUE NOT NULL REFERENCES mobile_devices(device_uuid),
    transfer_state TEXT NOT NULL,
    transfer_state_updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mobile_backup_sessions (
    session_id TEXT PRIMARY KEY,
    device_uuid TEXT NOT NULL REFERENCES mobile_devices(device_uuid),
    folder_id INTEGER NOT NULL REFERENCES folders(id),
    status TEXT NOT NULL,
    started_at TEXT NOT NULL,
    paired_at TEXT,
    ended_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_mobile_backup_sessions_device_started_at
ON mobile_backup_sessions(device_uuid, started_at DESC);

CREATE TABLE IF NOT EXISTS mobile_assets (
    device_uuid TEXT NOT NULL REFERENCES mobile_devices(device_uuid),
    remote_asset_id TEXT NOT NULL,
    remote_asset_version TEXT,
    local_relative_path TEXT NOT NULL,
    last_transferred_at TEXT NOT NULL,
    PRIMARY KEY (device_uuid, remote_asset_id)
);
"""


@dataclass(frozen=True)
class MobileFolderRecord:
    folder_id: int
    folder_path: str
    reused_existing: bool


@dataclass(frozen=True)
class MobileTransferContext:
    session_id: str
    device_uuid: str
    folder_id: int
    folder_path: str
    trust_key_b64: str


def ensure_mobile_pairing_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(_MOBILE_PAIRING_SCHEMA_SQL)
    conn.commit()


def get_or_create_desktop_device_id(conn: sqlite3.Connection) -> str:
    from dt_image_search.model.dt_device_id import get_device_id
    existing_value = get_config(conn, MOBILE_PAIRING_DESKTOP_DEVICE_ID_KEY)
    if existing_value:
        return existing_value

    desktop_device_id = uuid.UUID(get_device_id()).hex
    set_config(conn, MOBILE_PAIRING_DESKTOP_DEVICE_ID_KEY, desktop_device_id)
    return desktop_device_id


def derive_pairing_key_b64(
    *,
    session_id: str,
    one_time_passcode: str,
    device_uuid: str,
    platform: str,
    client_nonce: str,
    server_nonce: str,
    desktop_device_id: str,
) -> str:
    material = "\n".join(
        [
            "dtis.mobile-pairing.v1",
            session_id,
            one_time_passcode,
            device_uuid,
            platform,
            client_nonce,
            server_nonce,
            desktop_device_id,
        ]
    ).encode("utf-8")
    return base64.urlsafe_b64encode(hashlib.sha256(material).digest()).decode("ascii").rstrip("=")


def upsert_mobile_device(
    conn: sqlite3.Connection,
    *,
    device_uuid: str,
    platform: str,
    device_name: str,
    trust_key_b64: str,
    paired_at: datetime,
) -> None:
    timestamp = paired_at.isoformat()
    conn.execute(
        """
        INSERT INTO mobile_devices (
            device_uuid,
            platform,
            device_name,
            trust_key_b64,
            paired_at,
            last_seen_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(device_uuid) DO UPDATE SET
            platform = excluded.platform,
            device_name = excluded.device_name,
            trust_key_b64 = excluded.trust_key_b64,
            last_seen_at = excluded.last_seen_at
        """,
        (device_uuid, platform, device_name, trust_key_b64, timestamp, timestamp),
    )
    conn.commit()


def get_or_create_mobile_folder(
    conn: sqlite3.Connection,
    *,
    destination_parent: str,
    device_uuid: str,
    device_name: str,
    updated_at: datetime,
) -> MobileFolderRecord:
    existing_folder = conn.execute(
        """
        SELECT folders.id AS folder_id, folders.path AS folder_path
        FROM mobile_folders
        JOIN folders ON folders.id = mobile_folders.folder_id
        WHERE mobile_folders.device_uuid = ?
        """,
        (device_uuid,),
    ).fetchone()
    if existing_folder is not None:
        conn.execute(
            """
            UPDATE mobile_folders
            SET transfer_state = ?, transfer_state_updated_at = ?
            WHERE device_uuid = ?
            """,
            (MOBILE_TRANSFER_STATE_PAIRED, updated_at.isoformat(), device_uuid),
        )
        conn.commit()
        return MobileFolderRecord(
            folder_id=int(existing_folder["folder_id"]),
            folder_path=existing_folder["folder_path"],
            reused_existing=True,
        )

    destination_root = Path(destination_parent).expanduser().resolve()
    folder_name = _unique_mobile_folder_name(conn, destination_root=destination_root, device_name=device_name, device_uuid=device_uuid)
    folder_path = (destination_root / folder_name).resolve()
    folder_path.mkdir(parents=True, exist_ok=True)
    normalized_folder_path = folder_path.as_posix()

    folder = insert_folder(conn, normalized_folder_path)
    if folder is None:
        folder = _get_exact_folder(conn, normalized_folder_path)
    if folder is None:
        raise RuntimeError(f"Failed to create or load mobile folder row for path {normalized_folder_path}")

    conn.execute(
        """
        INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
        VALUES (?, ?, ?, ?)
        """,
        (_folder_id(folder), device_uuid, MOBILE_TRANSFER_STATE_PAIRED, updated_at.isoformat()),
    )
    conn.commit()
    return MobileFolderRecord(folder_id=_folder_id(folder), folder_path=normalized_folder_path, reused_existing=False)


def insert_mobile_backup_session(
    conn: sqlite3.Connection,
    *,
    session_id: str,
    device_uuid: str,
    folder_id: int,
    status: str,
    started_at: datetime,
    paired_at: datetime,
) -> None:
    conn.execute(
        """
        INSERT INTO mobile_backup_sessions (
            session_id,
            device_uuid,
            folder_id,
            status,
            started_at,
            paired_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (session_id, device_uuid, folder_id, status, started_at.isoformat(), paired_at.isoformat()),
    )
    conn.commit()


def get_mobile_transfer_context(
    conn: sqlite3.Connection,
    *,
    session_id: str,
    device_uuid: str,
    trust_key_b64: str,
) -> MobileTransferContext | None:
    row = conn.execute(
        """
        SELECT
            mobile_backup_sessions.session_id AS session_id,
            mobile_backup_sessions.device_uuid AS device_uuid,
            mobile_backup_sessions.folder_id AS folder_id,
            folders.path AS folder_path,
            mobile_devices.trust_key_b64 AS trust_key_b64
        FROM mobile_backup_sessions
        JOIN mobile_devices ON mobile_devices.device_uuid = mobile_backup_sessions.device_uuid
        JOIN folders ON folders.id = mobile_backup_sessions.folder_id
        WHERE mobile_backup_sessions.session_id = ?
          AND mobile_backup_sessions.device_uuid = ?
        """,
        (session_id, device_uuid),
    ).fetchone()
    if row is None:
        return None
    if row["trust_key_b64"] != trust_key_b64:
        return None
    return MobileTransferContext(
        session_id=row["session_id"],
        device_uuid=row["device_uuid"],
        folder_id=int(row["folder_id"]),
        folder_path=row["folder_path"],
        trust_key_b64=row["trust_key_b64"],
    )


def get_mobile_asset_record(
    conn: sqlite3.Connection,
    *,
    device_uuid: str,
    remote_asset_id: str,
):
    return conn.execute(
        """
        SELECT device_uuid, remote_asset_id, remote_asset_version, local_relative_path, last_transferred_at
        FROM mobile_assets
        WHERE device_uuid = ? AND remote_asset_id = ?
        """,
        (device_uuid, remote_asset_id),
    ).fetchone()


def upsert_mobile_asset_record(
    conn: sqlite3.Connection,
    *,
    device_uuid: str,
    remote_asset_id: str,
    remote_asset_version: str | None,
    local_relative_path: str,
    last_transferred_at: datetime,
) -> None:
    conn.execute(
        """
        INSERT INTO mobile_assets (
            device_uuid,
            remote_asset_id,
            remote_asset_version,
            local_relative_path,
            last_transferred_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(device_uuid, remote_asset_id) DO UPDATE SET
            remote_asset_version = excluded.remote_asset_version,
            local_relative_path = excluded.local_relative_path,
            last_transferred_at = excluded.last_transferred_at
        """,
        (
            device_uuid,
            remote_asset_id,
            remote_asset_version,
            local_relative_path,
            last_transferred_at.isoformat(),
        ),
    )
    conn.commit()


def update_mobile_transfer_state(
    conn: sqlite3.Connection,
    *,
    session_id: str,
    device_uuid: str,
    session_status: str,
    folder_transfer_state: str,
    updated_at: datetime,
    ended_at: datetime | None = None,
) -> None:
    conn.execute(
        """
        UPDATE mobile_backup_sessions
        SET status = ?, ended_at = COALESCE(?, ended_at)
        WHERE session_id = ? AND device_uuid = ?
        """,
        (
            session_status,
            ended_at.isoformat() if ended_at is not None else None,
            session_id,
            device_uuid,
        ),
    )
    conn.execute(
        """
        UPDATE mobile_folders
        SET transfer_state = ?, transfer_state_updated_at = ?
        WHERE device_uuid = ?
        """,
        (folder_transfer_state, updated_at.isoformat(), device_uuid),
    )
    conn.commit()


def _unique_mobile_folder_name(
    conn: sqlite3.Connection,
    *,
    destination_root: Path,
    device_name: str,
    device_uuid: str,
) -> str:
    base_name = _sanitize_folder_name(device_name)
    candidate_names = [base_name, f"{base_name}-{device_uuid[:8]}"]

    for candidate_name in candidate_names:
        candidate_path = (destination_root / candidate_name).as_posix()
        if _get_exact_folder(conn, candidate_path) is None:
            return candidate_name

    suffix = 2
    while True:
        candidate_name = f"{base_name}-{device_uuid[:8]}-{suffix}"
        candidate_path = (destination_root / candidate_name).as_posix()
        if _get_exact_folder(conn, candidate_path) is None:
            return candidate_name
        suffix += 1


def _sanitize_folder_name(device_name: str) -> str:
    sanitized_value = re.sub(r'[<>:"/\\\\|?*\x00-\x1f]+', "-", device_name).strip().strip(".")
    sanitized_value = re.sub(r"\s+", " ", sanitized_value)
    if sanitized_value:
        return sanitized_value
    return "Mobile Device"


def _get_exact_folder(conn: sqlite3.Connection, folder_path: str):
    row = conn.execute(
        "SELECT id, path, status, added_at FROM folders WHERE path = ?",
        (folder_path,),
    ).fetchone()
    if row is None:
        return None
    return row


def _folder_id(folder) -> int:
    if hasattr(folder, "id"):
        return int(folder.id)
    return int(folder["id"])
