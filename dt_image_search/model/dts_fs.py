from pathlib import Path
import threading
from PySide6.QtCore import QStandardPaths

_data_path = None
_data_lock = threading.Lock()

def get_app_data_path() -> Path:
    global _data_path
    # Add a lock to protect against reentrant calls
    with _data_lock:
        if _data_path is None:
            APP_NAME = "DTImageSearch"
            base_path = QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)
            _data_path = Path(base_path) / APP_NAME
            _data_path.mkdir(parents=True, exist_ok=True)
    return _data_path

def get_pretrained_model_cache_path() -> Path:
    return get_app_data_path() / "hf_cache"
