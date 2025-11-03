import os
from pathlib import Path
import threading
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.model.dts_db import get_all_folders
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.tools.dts_event_bus import default_bus
from dt_image_search.bm_context import BMContext
from dt_image_search.tools.dts_util import back_slash_to_forward_slash, normalized_folder_path
from dt_image_search.fs.bm_wrapped_watchdog_event import WrappedWatchdogEvent

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
_parent_folder_watch_map: dict[str, int] = {}

def start_watch(ctx: BMContext):
    def _observer_thread():
        with create_db_conn(ctx=ctx) as conn:
            for folder in get_all_folders(conn):
                add_folder(folder.path)

        _fs_observer.start()

    global _fs_observer, _fs_handler, _fs_handler_thread
    with _lock:
        if _fs_observer is None:
            _fs_observer = Observer()
            _fs_handler = FSHandler()
            _fs_handler_thread = threading.Thread(target=_observer_thread, daemon=True)
    _fs_handler_thread.start()

def stop_watch():
    global _fs_observer, _folder_watch_map, _parent_folder_watch_map
    if _fs_observer is not None:
        _fs_observer.stop()
        _fs_observer.join()
    with _lock:
        _fs_observer = None
        _folder_watch_map.clear()
        _parent_folder_watch_map.clear()

def add_folder(path: str):
    path = normalized_folder_path(path).replace('\\', '/')
    with _lock:
        # if _fs_observer is not None:
        #     _fs_observer.schedule(_fs_handler, path=path, recursive=True)
        if not Path(path).exists():
            log("warning", message=f"Folder does not exist, cannot watch: {path}")
            return

        try:
            _watch = _fs_observer.schedule(_fs_handler, path=path, recursive=True)
            _folder_watch_map[path] = _watch
        except Exception as e:
            log("error", message=f"Error watching folder {path}: {e}")

        root_folder_parent = normalized_folder_path(str(Path(path).parent)).replace('\\', '/')
        if root_folder_parent not in _parent_folder_watch_map:
            _parent_folder_watch_map[root_folder_parent] = _fs_observer.schedule(_fs_handler, path=root_folder_parent, recursive=False)

def remove_folder(path: str):
    path = normalized_folder_path(path).replace('\\', '/')
    with _lock:
        try:
            if not _fs_observer:
                return
            
            if not path in _folder_watch_map:
                return

            watch = _folder_watch_map.pop(path)
            _fs_observer.unschedule(watch)

            root_folder_parent = Path(path).parent
            if root_folder_parent in _parent_folder_watch_map:
                # Check if any other root folders are under this parent
                still_watched = False
                for watched_path in _folder_watch_map.keys():
                    if Path(watched_path).parent == root_folder_parent:
                        still_watched = True
                        break
                if not still_watched:
                    watch = _parent_folder_watch_map.pop(root_folder_parent)
                    _fs_observer.unschedule(watch)

        except Exception as e:
            log("error", message=f"Error unwatching folder {path}: {e}")

def _on_fs_changed(event):
    event = WrappedWatchdogEvent(event)

    log("debug", message=f"Directory changed: {event.event_type}")

    # filter out events that are not relevant to root folders
    with _lock:
        for root_folder in _folder_watch_map.keys():
            if normalized_folder_path(event.src_path).startswith(root_folder):
                default_bus.publish("fs_changed", event=event)
                break

    # the deleted file may be a root folder. We can not be sure of a directory deletion because is_directory may be False even for directory deletion events.
    if event.event_type == 'deleted':
        remove_folder(event.src_path)
