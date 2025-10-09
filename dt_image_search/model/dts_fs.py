import os
from pathlib import Path
import threading
from PySide6.QtCore import QStandardPaths

_data_lock = threading.Lock()

def get_app_data_path() -> Path:
    # Add a lock to protect against reentrant calls
    with _data_lock:
        if not os.getenv("BM_DATA_PATH"):
            APP_NAME = "DTImageSearch"
            _base_path = QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)
            _data_path = Path(_base_path) / APP_NAME
            _data_path.mkdir(parents=True, exist_ok=True)
            os.environ["BM_DATA_PATH"] = str(_data_path)
    return Path(os.getenv("BM_DATA_PATH"))

def get_pretrained_model_cache_path() -> Path:
    return get_app_data_path() / "hf_cache"
