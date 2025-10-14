import datetime
import os
import threading
from dt_image_search.model.dts_folder import Folder
from dt_image_search.index.dts_index import (
    index_path_for_folder,
    build_index,
    supported_image_types,
    append_to_index)
from dt_image_search.model.dts_db import create_db_conn, insert_file, update_folder_status, get_direct_child_files, mark_files_deleted, match_parent_folder
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.index.index_worker import resume_index_workers
from dt_image_search.tools.dts_event_bus import default_bus
from dt_image_search.bm_context import BMContext 

_max_activate = 4  # Maximum number of workers to activate at once
_index_workers = []  # List to keep track of active indexing workers
_workers_lock = threading.Lock()  # Protect _index_workers from concurrent access

class IncrementalIndexWorker:
    def __init__(self, ctx: BMContext, folder_path: str, files: list[str]):
        self.ctx = ctx
        self.folder_path = folder_path
        self.files = [f for f in files if os.path.isfile(f) and f.lower().endswith(supported_image_types)]
        self._thread = None
        self._is_stopped = False
        self.active = False

    def run(self):
        # start the indexing process in a separate thread
        self._is_stopped = False
        self.active = True
        self._thread = threading.Thread(target=self._run_impl, daemon=True)
        self._thread.start()
        
    def stop(self):
        """
        Stop the indexing process.
        """
        self.active = False
        self._is_stopped = True

    def _run_impl(self):
        try:
            # Check if the worker is stopped regularly to avoid unnecessary processing
            with create_db_conn(ctx=self.ctx) as conn:
                folderId2FilePaths = {}
                folderId2Folders = {}
                for file_path in self.files:
                    parent_folder = match_parent_folder(conn, file_path)
                    if parent_folder:
                        folderId2FilePaths.setdefault(parent_folder.id, []).append(file_path)
                        folderId2Folders.setdefault(parent_folder.id, parent_folder)
                # Mark non-existing subtree files as deleted
                _subtree_files = get_direct_child_files(conn, self.folder_path)
                _current_files_set = set(self.files)
                deleted_files = [f for f in _subtree_files if f.path not in _current_files_set]
                if deleted_files:
                    log("info", message=f"Marking {len(deleted_files)} files as deleted in subtree: {self.folder_path}")
                    mark_files_deleted(conn, [file.id for file in deleted_files])

                if not folderId2FilePaths:
                    log("info", message="No files to incrementally index.")
                    return

                status_bar_messenger.show_status_message.emit(f"Incremental updating index...")

                for folder_id, files in folderId2FilePaths.items():
                    folder = folderId2Folders.get(folder_id)
                    log("info", message=f"Incremental indexing for folder: {folder_id} with {len(files)} new files")
                    update_folder_status(conn, folder_id, 3)  # Set status to partially indexed
                    for file in files:
                        insert_file(conn, file, folder_id)

                    all_success = True
                    for progress in append_to_index(self.ctx, index_path_for_folder(self.ctx, folder), folder_id, files):
                        log("debug", message=f"Index progress: {progress['files_processed']}/{progress['total_files']} files processed")
                        if self._is_stopped:
                            log("info", message="Incremental indexing stopped by user.")
                            return
                    if not progress['batch_result']:
                        all_success = False

                    if all_success:
                        update_folder_status(conn, folder_id, 2)  # Set status to fully indexed
                    else:
                        update_folder_status(conn, folder_id, 1)  # For failing case, set status to indexing so that it can be picked up by index_worker
                        resume_index_workers(ctx=self.ctx)
                status_bar_messenger.show_status_message.emit(f"Incremental updating index completed.")
        finally:
            # Always remove worker from list when done, even if an exception occurred
            with _workers_lock:
                if self in _index_workers:
                    _index_workers.remove(self)
            _try_activate_workers()

def _add_incremental_index_worker(ctx: BMContext, path: str, files: list[str]):
    """
    Add a new indexing worker for the specified folder.
    """
    with _workers_lock:
        log("info", message=f"Creating new incremental index worker for files: {len(files)}")
        worker = IncrementalIndexWorker(ctx=ctx, folder_path=path, files=files)
        _index_workers.append(worker)
    _try_activate_workers()

def _try_activate_workers():
    # Activate at most _max_activate workers if they are idle
    with _workers_lock:
        active_workers = [w for w in _index_workers if w.active]
        idle_workers = [w for w in _index_workers if not w.active]
        if len(active_workers) >= _max_activate:
            return
        log("debug", message=f"Active workers: {len(active_workers)}, Idle workers: {len(idle_workers)}")
        for worker in idle_workers[:_max_activate - len(active_workers)]:
            worker.run()

def init_incremental_index_workers(ctx: BMContext):
    def _on_directory_changed(path):
        if not os.path.isdir(path):
            log("warning", message=f"Path does not exist: {path}")
            return
        child_files = []
        for child in os.listdir(path):
            child_path = os.path.join(path, child)
            if os.path.isfile(child_path):
                child_files.append(child_path)
        _add_incremental_index_worker(ctx, path, child_files)
    default_bus.subscribe("directory_changed", _on_directory_changed)