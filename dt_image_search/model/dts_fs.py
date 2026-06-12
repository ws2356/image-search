import os
from pathlib import Path
import threading
from PySide6.QtCore import QStandardPaths
from dt_image_search.build_flavor import get_build_type, BUILD_TYPE_DEV

_data_lock = threading.Lock()

def get_app_private_name() -> str:
    return "DTImageSearch-dev" if get_build_type() == BUILD_TYPE_DEV else "DTImageSearch"


def get_app_data_path() -> Path:
    app_data_segment = get_app_private_name()
    # Add a lock to protect against reentrant calls
    data_path_cache_key = f"BM_DATA_PATH_{app_data_segment}"
    with _data_lock:
        if not os.getenv(data_path_cache_key):
            _base_path = QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)
            _data_path = Path(_base_path) / app_data_segment
            _data_path.mkdir(parents=True, exist_ok=True)
            os.environ[data_path_cache_key] = str(_data_path)
    return Path(os.getenv(data_path_cache_key))
