import os
from pathlib import Path
import threading
from PySide6.QtCore import QStandardPaths
from dt_image_search.bm_context import BMContext

_data_lock = threading.Lock()

def get_app_data_path(ctx: BMContext) -> Path:
    # Add a lock to protect against reentrant calls
    with _data_lock:
        if not os.getenv("BM_DATA_PATH"):
            APP_NAME = "DTImageSearch"
            _base_path = QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)
            _data_path = Path(_base_path) / APP_NAME
            if ctx.subfolder:
                _data_path = _data_path / ctx.subfolder
            _data_path.mkdir(parents=True, exist_ok=True)
            os.environ["BM_DATA_PATH"] = str(_data_path)
    return Path(os.getenv("BM_DATA_PATH"))