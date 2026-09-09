import os
from pathlib import Path
import threading
from PySide6.QtCore import QStandardPaths
from pc_common.build_flavor import BUILD_TYPE_DEV, DesktopApp, get_build_type, get_desktop_app

_data_lock = threading.Lock()


def get_app_private_name() -> str:
    if get_desktop_app() == DesktopApp.SNAP_GET:
        return "SnapGet-dev" if get_build_type() == BUILD_TYPE_DEV else "SnapGet"
    return "DTImageSearch-dev" if get_build_type() == BUILD_TYPE_DEV else "DTImageSearch"


def get_app_data_path() -> Path:
    app_data_segment = get_app_private_name()
    # Add a lock to protect against reentrant calls
    # Caching this in an env var so that child processes can also access the same path without recalculating it
    # One caveat: parent process must call this first
    data_path_cache_key = f"BM_DATA_PATH_{app_data_segment}"
    with _data_lock:
        if not os.getenv(data_path_cache_key):
            _base_path = QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)
            _data_path = Path(_base_path) / app_data_segment
            _data_path.mkdir(parents=True, exist_ok=True)
            os.environ[data_path_cache_key] = str(_data_path)
    return Path(os.getenv(data_path_cache_key))
