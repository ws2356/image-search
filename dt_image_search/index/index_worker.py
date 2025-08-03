import datetime
import os
import threading
from dt_image_search.model.dts_folder import Folder
from dt_image_search.index.dts_index import (
    index_path_for_folder,
    build_index,
    supported_image_types)
from dt_image_search.model.dts_db import create_db_conn, insert_file, update_folder_status, get_all_folders
from dt_image_search.telemetry.telemetry_client import log

_max_workers = 4  # Maximum number of concurrent indexing workers
_index_workers = []  # List to keep track of active indexing workers
_workers_lock = threading.Lock()  # Protect _index_workers from concurrent access

class IndexWorker:
    def __init__(self, folder: Folder):
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
            with create_db_conn() as conn:
                folder_id = self.folder.id
                update_folder_status(conn, folder_id, 0)
                folder_path = self.folder.path
                # Enumerate images in the folder and add insert them into the database
                for root, _, fnames in os.walk(folder_path, followlinks=True):
                    for fname in fnames:
                        file_path = os.path.join(root, fname)
                        if os.path.isfile(file_path) and file_path.lower().endswith(supported_image_types):
                            log("debug", message=f"Inserting file: {file_path} into folder ID: {folder_id}")

                            insert_file(conn, file_path, folder_id)
                            if self._is_stopped:
                                log("info", message="Indexing stopped by user.")
                                return

                update_folder_status(conn, folder_id, 1)
                index_path = index_path_for_folder(self.folder)
                
                # Iterate over the build_index generator and check for stop condition
                for progress in build_index(index_path, folder_id):
                    if self._is_stopped:
                        log("info", message="Indexing stopped by user during build_index.")
                        return
                    log("debug", message=f"Index progress: {progress['files_processed']}/{progress['total_files']} files processed")
                
                update_folder_status(conn, folder_id, 2)
        finally:
            # Always remove worker from list when done, even if an exception occurred
            with _workers_lock:
                if self in _index_workers:
                    _index_workers.remove(self)

def add_index_worker(folder: Folder, replace_existing: bool = False) -> IndexWorker:
    """
    Add a new indexing worker for the specified folder.
    """
    with _workers_lock:
        existing_worker = next((w for w in _index_workers if w.folder.id == folder.id), None)
        if existing_worker:
            return existing_worker  # Return existing worker if already indexing this folder

        if len(_index_workers) >= _max_workers and not replace_existing:
            return None  # Cannot add more workers if the limit is reached
        
        if len(_index_workers) >= _max_workers:
            # Stop the oldest worker if replacing existing
            worker = _index_workers.pop(0)
            worker.stop()

        worker = IndexWorker(folder)
        _index_workers.append(worker)
        _index_workers.sort(key=lambda w: datetime.datetime.fromisoformat(w.folder.added_at))
    
    # Start the worker outside the lock to avoid holding the lock during thread creation
    worker.run()  
    return worker

_resume_thread = None
def resume_index_workers():
    global _resume_thread
    if _resume_thread is not None:
        return  # Resume thread is already running

    def resume_logic():
        with create_db_conn() as conn:
            folders = [folder for folder in get_all_folders(conn) if folder.status != 2]
            for folder in folders:
                if not add_index_worker(folder):
                    return
                log("info", message=f"Resuming indexing for folder: {folder.path}")
    _resume_thread = threading.Thread(target=resume_logic, daemon=True)
    _resume_thread.start()