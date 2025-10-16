import os
import threading
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from PySide6.QtCore import QFileSystemWatcher
from dt_image_search.index.incremental_index_worker import resume_index_workers
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.model.dts_db import get_all_folders
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.tools.dts_event_bus import default_bus
from dt_image_search.bm_context import BMContext

class FSHandler(FileSystemEventHandler):
    def on_created(self, event):
        _on_fs_changed(event=event)

    def on_deleted(self, event):
        _on_fs_changed(event=event)

    def on_modified(self, event):
        pass

    def on_moved(self, event):
        _on_fs_changed(event=event)

_fs_handler_thread: threading.Thread | None = None
_fs_observer: Observer | None = None
_fs_handler: FSHandler | None = None

_lock = threading.Lock()
_folder_watch_map: dict[str, int] = {}

def start_watch(ctx: BMContext):
    def _observer_thread():
        with create_db_conn(ctx=ctx) as conn:
            for folder in get_all_folders(conn):
                _watch = _fs_observer.schedule(_fs_handler, path=folder.path, recursive=True)
                with _lock:
                    _folder_watch_map[folder.path] = _watch
        _fs_observer.start()

    global _fs_observer, _fs_handler, _fs_handler_thread
    with _lock:
        if _fs_observer is None:
            _fs_observer = Observer()
            _fs_handler = FSHandler()
            _fs_handler_thread = threading.Thread(target=_observer_thread, daemon=True)
    _fs_handler_thread.start()

def stop_watch():
    if _fs_observer is not None:
        _fs_observer.stop()
        _fs_observer.join()
    with _lock:
        _fs_observer = None

def add_folder(path: str):
    with _lock:
        if _fs_observer is not None:
            _fs_observer.schedule(_fs_handler, path=path, recursive=True)

def remove_folder(path: str):
    with _lock:
        if _fs_observer is not None and path in _folder_watch_map:
            watch = _folder_watch_map.pop(path)
            _fs_observer.unschedule(watch)

def _on_fs_changed(event):
    log("debug", message=f"Directory changed: {event.event_type}")
    default_bus.publish("fs_changed", event=event)