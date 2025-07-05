import datetime
import logging
import os
import threading
from dt_image_search.model.folder import Folder
from dt_image_search.index.index import (
    index_path_for_folder,
    build_index,
    supported_image_types)
from dt_image_search.model.db import create_db_conn, insert_file, update_folder_status

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
                        logging.info(f"Inserting file: {file_path} into folder ID: {folder_id}")
                        insert_file(conn, file_path, folder_id)
                        if self._is_stopped:
                            logging.info("Indexing stopped by user.")
                            return

            update_folder_status(conn, folder_id, 1)
            index_path = index_path_for_folder(self.folder)
            build_index(index_path, folder_id)
            update_folder_status(conn, folder_id, 2)

_max_workers = 4  # Maximum number of concurrent indexing workers
_index_workers = []  # List to keep track of active indexing workers

def add_index_worker(folder: Folder, replace_existing: bool = False) -> IndexWorker:
    """
    Add a new indexing worker for the specified folder.
    """
    if len(_index_workers) >= _max_workers and not replace_existing:
        return None  # Cannot add more workers if the limit is reached
    
    if len(_index_workers) >= _max_workers:
        # Stop the oldest worker if replacing existing
        worker = _index_workers.pop(0)
        worker.stop()

    worker = IndexWorker(folder)
    _index_workers.append(worker)
    _index_workers.sort(key=lambda w: datetime.datetime.fromisoformat(w.folder.added_at))
    worker.run()  # Start the indexing process
    return worker