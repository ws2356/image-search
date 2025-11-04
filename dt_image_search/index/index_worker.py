import datetime
import os
import threading
from dt_image_search.model.dts_folder import Folder
from dt_image_search.index.dts_index import (
    index_path_for_folder,
    build_index,
    is_image_file)
from dt_image_search.model.dts_db import create_db_conn, insert_file, update_folder_status, get_all_folders, get_folder_by_path
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_util import normalized_folder_path
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext
from dt_image_search.tools.dts_event_bus import default_bus

_max_workers = 4  # Maximum number of concurrent indexing workers
_index_workers = []  # List to keep track of active indexing workers
_workers_lock = threading.Lock()  # Protect _index_workers from concurrent access

class IndexWorker:
    def __init__(self, ctx: BMContext, folder: Folder):
        self.ctx = ctx
        self.folder = folder
        self._thread = None
        self._is_stopped = False

    def run(self):
        # start the indexing process in a separate thread
        self._thread = threading.Thread(target=self._run_impl, daemon=True)
        self._thread.start()
        
    def stop(self):
        """
        Stop the indexing process.
        """
        self._is_stopped = True

    def _run_impl(self):
        try:
            # Check if the worker is stopped regularly to avoid unnecessary processing
            with create_db_conn(ctx=self.ctx) as conn:
                status_bar_messenger.show_status_message.emit(f"Indexing folder: {self.folder.path}")

                folder_id = self.folder.id
                update_folder_status(conn, folder_id, 0)
                folder_path = self.folder.path

                def _traverse_dir(folder_path: str):
                    if self._is_stopped:
                        return
                    # traverse folder_path non recursively
                    for entry in os.scandir(folder_path):
                        _filepath = entry.path
                        if entry.is_dir():
                            _subfolder = get_folder_by_path(conn, normalized_folder_path(_filepath))
                            if _subfolder:
                                continue
                            else:
                                _traverse_dir(_filepath)
                        elif entry.is_file() and is_image_file(_filepath):
                            insert_file(conn, _filepath, folder_id)

                _traverse_dir(folder_path=folder_path)
                if self._is_stopped:
                    log("info", message="Indexing stopped by user.")
                    status_bar_messenger.show_status_message.emit(f"Indexing canceled: {self.folder.path}")
                    return

                update_folder_status(conn, folder_id, 1)
                index_path = index_path_for_folder(self.ctx, self.folder)
                
                all_success = True
                # Iterate over the build_index generator and check for stop condition
                for progress in build_index(ctx=self.ctx, index_path=index_path, folder_id=folder_id):
                    if self._is_stopped:
                        log("info", message="Indexing stopped by user during build_index.")
                        status_bar_messenger.show_status_message.emit(f"Indexing canceled: {self.folder.path}")
                        return
                    log("debug", message=f"Index progress: {progress['files_processed']}/{progress['total_files']} files processed")
                    status_bar_messenger.show_status_message.emit(f"Indexing folder ({self.folder.path}) - {progress['files_processed']}/{progress['total_files']} files processed")
                    if not progress['batch_result']:
                        all_success = False
                
                if all_success:
                    log("info", message="Indexing succeeded.")
                    update_folder_status(conn, folder_id, 2)
                    status_bar_messenger.show_status_message.emit(f"Indexing completed: {self.folder.path}")
                else:
                    status_bar_messenger.show_status_message.emit(f"Indexing partially failed.")
        finally:
            # Always remove worker from list when done, even if an exception occurred
            with _workers_lock:
                if self in _index_workers:
                    _index_workers.remove(self)
                    # Try to activate other workers if any are idle
                    with create_db_conn(ctx=self.ctx) as conn:
                        folder = get_folder_by_path(conn, self.folder.path)
                        # Only recur if the previous folder was completed to avoid infinite loops
                        if folder is None or folder.status == 2:
                            resume_index_workers(self.ctx)

def add_index_worker(ctx: BMContext, folder: Folder, replace_existing: bool = False) -> IndexWorker:
    """
    Add a new indexing worker for the specified folder.
    """
    with _workers_lock:
        existing_worker = next((w for w in _index_workers if w.folder.id == folder.id), None)
        if existing_worker:
            log("info", message=f"Index worker already exists for this folder: {folder.id}.")
            return existing_worker  # Return existing worker if already indexing this folder

        if len(_index_workers) >= _max_workers and not replace_existing:
            return None  # Cannot add more workers if the limit is reached
        
        if len(_index_workers) >= _max_workers:
            # Stop the oldest worker if replacing existing
            worker = _index_workers.pop(0)
            worker.stop()

        log("info", message=f"Index worker not already exists for this folder: {folder.id}, creating one")
        worker = IndexWorker(ctx, folder)
        _index_workers.append(worker)
        _index_workers.sort(key=lambda w: datetime.datetime.fromisoformat(w.folder.added_at))
    
    # Start the worker outside the lock to avoid holding the lock during thread creation
    worker.run()  
    return worker

def resume_index_workers(ctx: BMContext, is_init: bool = False):
    folder_statuses_to_resume = [0, 1]  # Not indexed or partially indexed
    if is_init:
        folder_statuses_to_resume.append(3)  # Also include partially updated on init

    log("info", message=f"Resuming index workers for incomplete folders.")
    def resume_logic():
        with create_db_conn(ctx=ctx) as conn:
            log("info", message="Resuming index workers for incomplete folders - db connected")
            all_folders = get_all_folders(conn)
            folders = [folder for folder in all_folders if folder.status in folder_statuses_to_resume]
            for folder in folders:
                if not add_index_worker(ctx, folder):
                    return
                log("info", message=f"Resuming indexing for folder: {folder.path}")
    _resume_thread = threading.Thread(target=resume_logic, daemon=True)
    _resume_thread.start()

_subscription = None

def init_index_workers(ctx: BMContext):
    global _subscription
    resume_index_workers(ctx, is_init=True)
    def _stop_deleted_worker_for_folder(folder_path: str):
        normalized_path = normalized_folder_path(folder_path).replace('\\', '/')
        with _workers_lock:
            worker = next((w for w in _index_workers if w.folder.path == normalized_path), None)
            if worker:
                log("info", message=f"Stopping index worker for deleted folder: {normalized_path}")
                worker.stop()
                _index_workers.remove(worker)
    _subscription = default_bus.subscribe("folder_deleted_from_ui", _stop_deleted_worker_for_folder)

def deinit_index_workers():
    global _subscription
    if _subscription:
        _subscription.dispose()
        _subscription = None
    with _workers_lock:
        for worker in _index_workers:
            worker.stop()
        _index_workers.clear()