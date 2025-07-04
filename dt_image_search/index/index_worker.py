import datetime
from dt_image_search.model.folder import Folder

class IndexWorker:
    def __init__(self, folder: Folder):
        self.folder = folder

    def run(self):
        """
        Run the indexing process.
        """
        pass

    def stop(self):
        """
        Stop the indexing process.
        """
        pass

    def is_running(self):
        """
        Check if the indexing process is running.
        """
        pass

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