import os
import sys
from PySide6.QtCore import QFileSystemWatcher
from dt_image_search.index.incremental_index_worker import resume_index_workers
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.model.dts_db import get_all_folders
from dt_image_search.index.incremental_index_worker import add_incremental_index_worker
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.tools.dts_event_bus import default_bus

_watcher: QFileSystemWatcher | None = None

def start_watch():
    global _watcher
    if _watcher is None:
        _watcher = QFileSystemWatcher()
        _watcher.directoryChanged.connect(on_directory_changed)
        log("debug", message="File system watcher started.")
    with create_db_conn() as conn:
        for folder in get_all_folders(conn):
            add_path(folder.path)

def stop_watch():
    global _watcher
    if _watcher is not None:
        _watcher.directoryChanged.disconnect(on_directory_changed)
        _watcher.removePaths(_watcher.directories())
        _watcher = None
        log("debug", message="File system watcher stopped.")

def add_path(path: str):
    global _watcher
    if _watcher is None:
        log("warning", message="File system watcher is not started.")
        return
    if not os.path.isdir(path):
        log("warning", message=f"Path does not exist: {path}")
        return
    try:
      _watcher.addPath(path)
      log("debug", message=f"Watching directory: {path}")
    except Exception as e:
        log("error", message=f"Failed to add path to watcher: {e}")
        return
    # enumerate directory contents in path and recursively add subdirectories
    for child in os.listdir(path):
        child_path = os.path.join(path, child)
        if os.path.isdir(child_path):
            add_path(child_path)

def on_directory_changed(path):
    log("debug", message=f"Directory changed: {path}")
    default_bus.publish("directory_changed", path=path)