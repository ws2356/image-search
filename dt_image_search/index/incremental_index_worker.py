import os
import threading
import watchdog
from dt_image_search.index.dts_index import (
    index_path_for_folder,
    is_image_file,
    append_to_index,
    delete_folder)
from dt_image_search.model.dts_db import (
    create_db_conn,
    insert_file,
    update_folder_status,
    delete_files_by_ids,
    match_parent_folder,
    get_folder_by_path,
    get_file_by_path,
    match_child_files,
    is_folder_exists,
    rename_file,
    rename_files_in_folder
)
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.index.index_worker import resume_index_workers
from dt_image_search.tools.dts_event_bus import default_bus
from dt_image_search.bm_context import BMContext 

_index_workers = []  # List to keep track of active indexing workers
_workers_lock = threading.Lock()  # Protect _index_workers from concurrent access

class BaseIncrementalIndexWorker:
    def stop(self):
        raise NotImplementedError()
class FileCreationIndexWorker(BaseIncrementalIndexWorker):
    def __init__(self, ctx: BMContext, events: list[watchdog.events.FileCreatedEvent]):
        self.ctx = ctx
        self.events = events
        self._thread = None
        self._is_stopped = False
        self.active = False

    def run(self):
        # start the indexing process in a separate thread
        self._is_stopped = False
        self.active = True
        self._thread = threading.Thread(target=self._run_impl, daemon=False)
        self._thread.start()
        
    def stop(self):
        """
        Stop the indexing process.
        """
        self.active = False
        self._is_stopped = True

    def _run_impl(self):
        try:
            all_files = []
            for event in self.events:
                if os.path.isfile(event.src_path) and is_image_file(event.src_path):
                    all_files.append(event.src_path)
            if not all_files:
                log("debug", message="No files to incrementally index.")
                return

            # Check if the worker is stopped regularly to avoid unnecessary processing
            with create_db_conn(ctx=self.ctx) as conn:
                folderId2FilePaths = {}
                folderId2Folders = {}
                for file_path in all_files:
                    parent_folder = match_parent_folder(conn, file_path)
                    if parent_folder:
                        folderId2FilePaths.setdefault(parent_folder.id, []).append(file_path)
                        folderId2Folders.setdefault(parent_folder.id, parent_folder)

                if not folderId2FilePaths:
                    log("info", message="No files to incrementally index.")
                    return

                status_bar_messenger.show_status_message.emit(f"Indexing new files...")

                for folder_id, files in folderId2FilePaths.items():
                    folder = folderId2Folders.get(folder_id)
                    log("info", message=f"Indexing new files for folder: {folder_id} with {len(files)} new files")
                    update_folder_status(conn, folder_id, 3)  # Set status to partially indexed
                    for file in files:
                        insert_file(conn, file, folder_id)

                    all_success = True
                    for progress in append_to_index(self.ctx, index_path_for_folder(self.ctx, folder), folder_id, files):
                        log("debug", message=f"Index progress: {progress['files_processed']}/{progress['total_files']} files processed")
                        if self._is_stopped:
                            log("info", message="Incremental indexing stopped by user.")
                            return

                        if not is_folder_exists(conn, folder.path):
                            log("info", message=f"Folder {folder.path} has been deleted during incremental indexing. Aborting indexing for this folder.")
                            break

                    if not is_folder_exists(conn, folder.path):
                        continue

                    if not progress['batch_result']:
                        all_success = False

                    if all_success:
                        update_folder_status(conn, folder_id, 2)  # Set status to fully indexed
                    else:
                        update_folder_status(conn, folder_id, 1)  # For failing case, set status to indexing so that it can be picked up by index_worker
                        resume_index_workers(ctx=self.ctx)
                status_bar_messenger.show_status_message.emit(f"Incremental updating index completed.")
        finally:
            # Always remove worker from list when done, even if an exception occurred
            with _workers_lock:
                if self in _index_workers:
                    _index_workers.remove(self)
            if not self._is_stopped:
                _try_schedule_next_batch(self.ctx)

def _on_created(ctx: BMContext, events: list[watchdog.events.FileCreatedEvent]):
    # Spawn one worker for every 100 events
    batch_size = 100
    for i in range(0, len(events), batch_size):
        worker = FileCreationIndexWorker(ctx=ctx, events=events[i:i+batch_size])
        with _workers_lock:
            _index_workers.append(worker)
        worker.run()

def _on_deleted(ctx: BMContext, events: list[watchdog.events.FileDeletedEvent]):
    status_bar_messenger.show_status_message.emit(f"File deletion started...")
    with create_db_conn(ctx=ctx) as conn:
        file_id_set = set()
        folder_id_folder_map = {}
        for event in events:
            direct_matched_file = get_file_by_path(conn, event.src_path)
            # deleted file is file
            if direct_matched_file:
                file_id_set.add(direct_matched_file.id)
            else:
                # deleted file is folder
                child_files = match_child_files(conn, event.src_path)
                for child_file in child_files:
                    file_id_set.add(child_file.id)
                
                # deleted file is root folder
                folder = get_folder_by_path(conn, event.src_path)
                if folder:
                    folder_id_folder_map[folder.id] = folder

        if not file_id_set and not folder_id_folder_map:
            return
        log("info", message=f"Marking {len(file_id_set)} files as deleted in the database.")
        delete_files_by_ids(conn, list(file_id_set))

        for folder in folder_id_folder_map.values():
            log("info", message=f"Deleting folder index for deleted folder: {folder}")
            delete_folder(ctx, folder.path)
    status_bar_messenger.show_status_message.emit(f"File deletion completed.")

def _on_moved(ctx: BMContext, events: list[watchdog.events.FileMovedEvent]):
    with create_db_conn(ctx=ctx) as conn:
        for event in events:
            if not rename_file(conn, event.src_path, event.dest_path):
                rename_files_in_folder(conn, event.src_path, event.dest_path)

_event_buffer = []
_event_buffer_lock = threading.Lock()
_fs_changed_subscription = None

def _try_schedule_next_batch(ctx: BMContext):
    global _event_buffer
    to_be_handled = []
    with _event_buffer_lock:
        if not _event_buffer or _index_workers:
            return
        event_type = _event_buffer[0].event_type
        for event in _event_buffer:
            if event.event_type == event_type:
                to_be_handled.append(event)
            else:
                break
        _event_buffer = _event_buffer[len(to_be_handled):]
    if to_be_handled:
        if event_type == 'created':
            _on_created(ctx, to_be_handled)
        elif event_type == 'deleted':
            _on_deleted(ctx, to_be_handled)
        elif event_type == 'moved':
            _on_moved(ctx, to_be_handled)

def init_incremental_index_workers(ctx: BMContext):
    global _fs_changed_subscription
    def _on_directory_changed(event):
        with _event_buffer_lock:
            _event_buffer.append(event)
        # delay for 1s before processing to batch events. Otherwise may hit 13 permission errors on Windows
        import time
        time.sleep(1)
        _try_schedule_next_batch(ctx=ctx)
    _fs_changed_subscription = default_bus.subscribe("fs_changed", _on_directory_changed)

def deinit_incremental_index_workers():
    global _event_buffer, _fs_changed_subscription
    if _fs_changed_subscription:
        _fs_changed_subscription.dispose()
        _fs_changed_subscription = None
    to_be_handled = []
    with _event_buffer_lock:
        to_be_handled = _event_buffer[:]
        _event_buffer = []
    if to_be_handled:
        # TODO: mark the affected folders as needing reindexing
        pass
    with _workers_lock:
        for worker in _index_workers:
            worker.stop()