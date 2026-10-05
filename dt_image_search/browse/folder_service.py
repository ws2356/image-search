# Folder registration/removal business logic, Qt-free.
# Shared by the legacy Qt BrowseController and the index server routes:
# register_folder owns the DB decision, watch_and_index owns the fs/indexing
# side effects so callers (UI vs server) compose them without duplication.
from dt_image_search.model.dts_db import (
    create_db_conn,
    get_folder_by_path,
    insert_folder,
    match_parent_folder,
    update_folder_status,
)
from dt_image_search.index.dts_index import delete_folder
from dt_image_search.index.index_worker import add_index_worker
from dt_image_search.fs.bm_fs_monitor import add_folder as watch_folder
from dt_image_search.fs.bm_fs_monitor import remove_folder as unwatch_folder
from dt_image_search.tools.dts_event_bus import default_bus
from dt_image_search.tools.dts_util import normalized_folder_path, is_same_folder_path
from pc_common.telemetry.telemetry_client import log
from dt_image_search.bm_context import BMContext
from dt_image_search.model.dts_folder import Folder


def register_folder(ctx: BMContext, folder_path: str) -> tuple[Folder | None, bool]:
    """Normalize and register a folder in the DB without side effects.

    Returns (folder, created). When the path is inside an already-registered
    folder, the parent Folder is returned with created=False and nothing is
    inserted. Returns (None, False) when the row could not be ensured.
    """
    folder_path = normalized_folder_path(folder_path).replace('\\', '/')
    with create_db_conn() as conn:
        parent_folder = match_parent_folder(conn, folder_path)
    if parent_folder and not is_same_folder_path(parent_folder.path, folder_path):
        log("debug", message=f"folder_service/register_folder: found parent folder {parent_folder.path}")
        return parent_folder, False

    with create_db_conn() as conn:
        folder = insert_folder(conn, folder_path)
        created = folder is not None
        if folder is None:
            folder = get_folder_by_path(conn, folder_path)
    if folder is None:
        log("error", message=f"folder_service/register_folder: failed to register folder {folder_path}")
        return None, False
    return folder, created


def watch_and_index(ctx: BMContext, folder: Folder) -> None:
    """Start watching a registered folder and enqueue it for indexing
    (skipped when the folder is already fully indexed)."""
    watch_folder(folder.path)
    if folder.status != 2:
        add_index_worker(ctx=ctx, folder=folder)


def remove_folder(ctx: BMContext, folder_path: str) -> None:
    """Unwatch, notify subscribers and delete the folder (and its files/index)
    from the DB."""
    log("info", message=f"folder_service/remove_folder: removing folder {folder_path}")
    unwatch_folder(folder_path)
    default_bus.publish("folder_deleted_from_ui", folder_path=folder_path)
    delete_folder(ctx=ctx, folder_path=folder_path)


def reindex_folder(ctx: BMContext, folder: Folder) -> None:
    """Reset a folder's status to pending and enqueue it for a fresh index run."""
    with create_db_conn() as conn:
        update_folder_status(conn, folder.id, 0)
    add_index_worker(ctx=ctx, folder=folder)
