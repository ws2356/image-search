# Qt-free search orchestration: merge per-folder CLIP index queries into one
# ranked result list. Shared by the legacy Qt controller and the index server.
from pathlib import Path

from dt_image_search.model.dts_db import create_db_conn, get_all_folders
from dt_image_search.index.dts_index import query_index, index_path_for_folder, TOP_K, get_model_state, MODEL_STATE_READY
from pc_common.telemetry.telemetry_client import log
from dt_image_search.bm_context import BMContext
from dt_image_search.model.dts_folder import Folder


class ModelNotReadyError(Exception):
    """Raised when the CLIP model cannot serve queries yet."""

    def __init__(self, state: str):
        self.state = state
        super().__init__(f"model not ready: {state}")


def search_folders(ctx: BMContext, query: str) -> list:
    """Search every registered folder and return up to TOP_K (file, score) pairs,
    sorted by descending score. Raises ModelNotReadyError when the model is
    loading or failed."""
    state = get_model_state()
    if state != MODEL_STATE_READY:
        raise ModelNotReadyError(state)

    results = []
    with create_db_conn() as conn:
        for folder in get_all_folders(conn):
            results.extend(_search_in_folder(ctx, folder, query))

    results.sort(key=lambda x: x[1], reverse=True)
    return results[:TOP_K]


def _search_in_folder(ctx: BMContext, folder: Folder, query: str) -> list:
    log("info", message=f"Searching in folder: {folder.path}")
    index_path = index_path_for_folder(folder=folder)
    if not Path(index_path).exists():
        log("warning", "search", message=f"Index file does not exist for folder: {folder.path}")
        return []
    items = query_index(ctx=ctx, folder_id=folder.id, index_path=index_path, query_text=query)
    for item in items:
        log("debug", message=f"Found item: {item[0]} with score: {item[1]}")
    return items
