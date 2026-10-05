# App data path resolution, Qt-free.
# Replicates the Qt entry's QStandardPaths.AppLocalDataLocation resolution
# EXACTLY — per-OS base + the org/app name segments installed by
# dt_image_search/app_setting.py (org=net.boldman, app=imagesearch[-dev]) —
# so the Qt-free shell/server read the same data directory as the Qt build.
# Pinned by tests/unit/test_dts_fs.py::TestQtFreeBasePathMatchesQt.
import os
import sys
import threading
from pathlib import Path

from pc_common.build_flavor import BUILD_TYPE_DEV, DesktopApp, get_build_type, get_desktop_app

_ORG_NAME = "net.boldman"
_APP_NAME = "imagesearch"

_data_lock = threading.Lock()


def get_app_private_name() -> str:
    if get_desktop_app() == DesktopApp.SNAP_GET:
        return "SnapGet-dev" if get_build_type() == BUILD_TYPE_DEV else "SnapGet"
    return "DTImageSearch-dev" if get_build_type() == BUILD_TYPE_DEV else "DTImageSearch"


def get_app_data_os_base_path() -> Path:
    """Per-OS base path matching QStandardPaths.AppDataLocation."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform == "win32":
        return Path(os.environ["LOCALAPPDATA"])
    # Unix: XDG_DATA_HOME, falling back to ~/.local/share
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def get_app_data_base_path() -> Path:
    """Base + the org/app segments the Qt app installs via app_setting.py."""
    app_name = f"{_APP_NAME}-dev" if get_build_type() == BUILD_TYPE_DEV else _APP_NAME
    return get_app_data_os_base_path() / _ORG_NAME / app_name


def get_app_data_path() -> Path:
    app_data_segment = get_app_private_name()
    # Add a lock to protect against reentrant calls
    # Caching this in an env var so that child processes can also access the same path without recalculating it
    # One caveat: parent process must call this first
    data_path_cache_key = f"BM_DATA_PATH_{app_data_segment}"
    with _data_lock:
        if not os.getenv(data_path_cache_key):
            _data_path = get_app_data_base_path() / app_data_segment
            _data_path.mkdir(parents=True, exist_ok=True)
            os.environ[data_path_cache_key] = str(_data_path)
    return Path(os.getenv(data_path_cache_key))
