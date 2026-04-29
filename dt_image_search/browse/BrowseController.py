import watchdog
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, QPersistentModelIndex, Qt, QModelIndex, Signal, QObject, QThread, QTimer
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.browse.fs_image_list_model import FSImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_TRANSFER_STATE_TRANSFERRING,
    get_mobile_folder_summaries_by_path,
    get_mobile_folder_transfer_states,
)
from dt_image_search.model.dts_db import create_db_conn, get_all_folders, get_folder_by_path, insert_folder, match_parent_folder
from dt_image_search.model.feature_flags import is_mobile_folder_enabled
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.index.dts_index import index_path_for_folder, delete_folder
from dt_image_search.tools.dts_debounce import debounce, throttle
from dt_image_search.index.index_worker import add_index_worker
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.fs.bm_fs_monitor import add_folder, remove_folder
from dt_image_search.bm_context import BMContext
from dt_image_search.tools.dts_util import is_same_folder_path, normalized_folder_path
from dt_image_search.tools.dts_event_bus import default_bus

_MOBILE_TRANSFER_STATUS_POLL_INTERVAL_MS = 1000

class BrowseController(BaseController):
    class FSChangedSignal(QObject):
        signal = Signal(watchdog.events.FileSystemEvent)

    class FolderSelectionSignal(QObject):
        select_folder = Signal(object)  # Signal to request folder selection in UI

    def __init__(self, ctx: BMContext):
        super().__init__()
        self.folderListModel = None
        self.ctx = ctx
        self.imageListModel = None
        self._init_folders()
        self._folder_changed_in_background = []
        self._fs_changed_signal = self.FSChangedSignal()
        self._fs_changed_signal.signal.connect(self._on_notify_folder_changed_main_thread)
        self._folder_selection_signal = self.FolderSelectionSignal()
        self._mobile_transfer_status_timer = QTimer()
        self._mobile_transfer_status_timer.setInterval(_MOBILE_TRANSFER_STATUS_POLL_INTERVAL_MS)
        self._mobile_transfer_status_timer.timeout.connect(self._on_mobile_transfer_status_poll_timeout)
        default_bus.subscribe("fs_changed", self._on_notify_folder_changed)
        self._selected_folder_path = ''

    def folder_list_model(self) -> FolderTreeModel:
        if self.folderListModel is None:
            self.folderListModel = self._create_model_for_folder()
        return self.folderListModel

    def image_list_model(self) -> ImageListModel:
        if self.imageListModel is None:
          self.imageListModel = FSImageListModel()
        return self.imageListModel

    @property
    def folder_selection_signal(self):
        """Access to the folder selection signal for connecting to UI."""
        return self._folder_selection_signal

    def on_folder_added(self, folder_path: str):
        log("debug", message=f"BrowseController/on_folder_added: adding folder {folder_path}")
        folder_path = normalized_folder_path(folder_path).replace('\\', '/')
        with create_db_conn(ctx=self.ctx) as conn:
            parent_folder = match_parent_folder(conn, folder_path)
        if parent_folder and not is_same_folder_path(parent_folder.path, folder_path):
            log("debug", message=f"BrowseController/on_folder_added: found parent folder {parent_folder.path}")
            folder_item = self.folder_list_model().find_folder_item(parent_folder.path)
            if folder_item:
                log("debug", message=f"BrowseController/on_folder_added: emitting select_folder for parent item {parent_folder.path}")
                self._folder_selection_signal.select_folder.emit(folder_item)
            else:
                log("warning", message=f"BrowseController/on_folder_added: parent folder item not found in model for {parent_folder.path}")
            return
        self.ensure_folder_registered(folder_path, insert_if_missing=True, select_folder=True)

    def ensure_folder_registered(self, folder_path: str, *, insert_if_missing: bool = False, select_folder: bool = False) -> None:
        folder_path = normalized_folder_path(folder_path).replace('\\', '/')
        with create_db_conn(ctx=self.ctx) as conn:
            folder = get_folder_by_path(conn, folder_path)
            if folder is None and insert_if_missing:
                folder = insert_folder(conn, folder_path)
                if folder is None:
                    folder = get_folder_by_path(conn, folder_path)
            if not folder:
                log("error", message=f"BrowseController/ensure_folder_registered: failed to load folder {folder_path} from DB")
                return

        self._refresh_mobile_transfer_states()
        fallback_item = self._ensure_folder_visible(folder.path)
        self._refresh_mobile_transfer_states()
        folder_item = self.folder_list_model().find_folder_item(folder.path) or fallback_item
        if folder_item is None:
            log("warning", message=f"BrowseController/ensure_folder_registered: folder item not found in model for {folder.path}")
            return

        if select_folder:
            log("debug", message=f"BrowseController/ensure_folder_registered: emitting select_folder for {folder.path}")
            self._folder_selection_signal.select_folder.emit(folder_item)

    def _ensure_folder_visible(self, folder_path: str) -> QStandardItem | None:
        is_mobile_folder = self.folder_list_model().is_mobile_folder_path(folder_path)
        if is_mobile_folder:
            existing_item = self.folder_list_model().find_folder_item(folder_path)
            if existing_item is not None and self.folder_list_model().is_top_level_folder_item(existing_item):
                return existing_item
            with create_db_conn(ctx=self.ctx) as conn:
                folder = get_folder_by_path(conn, folder_path)
            if folder is None:
                return None
            self.folder_list_model().add_root_folder([folder.path])
            add_folder(folder.path)
            if folder.status != 2:
                add_index_worker(ctx=self.ctx, folder=folder)
            return self.folder_list_model().find_folder_item(folder.path)

        containing_root = self.folder_list_model().get_containing_root_folder(folder_path)
        if containing_root is None:
            with create_db_conn(ctx=self.ctx) as conn:
                folder = get_folder_by_path(conn, folder_path)
            if folder is None:
                return None
            self.folder_list_model().add_root_folder([folder.path])
            add_folder(folder.path)
            if folder.status != 2:
                add_index_worker(ctx=self.ctx, folder=folder)
            return self.folder_list_model().find_folder_item(folder.path)

        containing_root_path = containing_root.data(Qt.UserRole) or ""
        if is_same_folder_path(containing_root_path, folder_path):
            return containing_root

        folder_item = self.folder_list_model().find_folder_item(folder_path)
        return folder_item or containing_root

    def on_folder_selected(self, current: QModelIndex, previous: QModelIndex):
        if not current.isValid():
            log("debug", message="BrowseController/on_folder_selected: current index invalid")
            return
        folder_path = current.data(Qt.UserRole)
        if not folder_path:
            log("warning", message="BrowseController/on_folder_selected: selected item has no path data")
            return
        self._selected_folder_path = folder_path
        log("info", message=f"on_folder_selected: {folder_path}")
        self.image_list_model().load_images_from_folder(folder_path)

    def on_item_expanded(self, index: QModelIndex):
        self.folder_list_model().expand_subfolders(index)

    def on_delete_folder(self, index: QPersistentModelIndex, data: str = None):
        log("info", message=f"Removing folder: {data}")
        log("debug", message=f"BrowseController/on_delete_folder: removing folder {data} from FS monitor")
        
        remove_folder(data)
        
        if self._selected_folder_path and data and normalized_folder_path(self._selected_folder_path) == normalized_folder_path(data):
            log("debug", message=f"BrowseController/on_delete_folder: clearing selection as selected folder is being deleted: {data}")
            self._selected_folder_path = ''
            self.image_list_model().load_images_from_paths([])
            
        default_bus.publish("folder_deleted_from_ui", folder_path=data)
        log("debug", message=f"BrowseController/on_delete_folder: deleting folder from model at index row {index.row()}")
        self.folder_list_model().deleteFolder(index)
        log("debug", message=f"BrowseController/on_delete_folder: deleting folder from DB/Index: {data}")
        delete_folder(ctx=self.ctx, folder_path=data)

    def _init_folders(self):
        self._refresh_mobile_transfer_states()
        _root_folders = self._load_folders()
        self.folder_list_model().add_root_folder(_root_folders)
        self._refresh_mobile_transfer_states()

    def _load_folders(self) -> list[str]:
        with create_db_conn(ctx=self.ctx) as conn:
            folders = get_all_folders(conn)
            mobile_folder_paths = set(get_mobile_folder_transfer_states(conn).keys())
            # sort folders asc
            folders.sort(key=lambda f: f.path)
            root_folders = []
            for item in folders:
                normalized_item_path = normalized_folder_path(item.path).replace('\\', '/')
                is_mobile_folder = normalized_item_path in mobile_folder_paths
                is_nested_under_existing_root = any(
                    normalized_item_path.startswith(normalized_folder_path(root_path).replace('\\', '/'))
                    for root_path in root_folders
                )
                if is_nested_under_existing_root and not is_mobile_folder:
                    continue
                root_folders.append(item.path)
            log("info", message=f"Loaded {len(root_folders)} root folders from the database.")
            return root_folders

    def _create_model_for_folder(self) -> QAbstractItemModel:
        model = FolderTreeModel(sectioned_view=is_mobile_folder_enabled())
        return model
    
    @throttle(3)  # Debounce search queries to avoid excessive calls
    def _on_notify_folder_changed(self, event):
        log("debug", message=f"BrowseController/_on_notify_folder_changed: event type={event.event_type}, src={event.src_path}")
        self._fs_changed_signal.signal.emit(event)

    def _on_notify_folder_changed_main_thread(self, event):
        # Assert main thread
        assert QThread.isMainThread()
        log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: processing event {event.event_type} for {event.src_path}")
        deleted_item = self._try_delete_root_folder(event) if event.event_type == 'deleted' else None
        if not deleted_item:
            log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: not a root deletion, relying on QFileSystemModel update for {event.src_path}")
        else:
             log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: root folder deleted: {event.src_path}")

        # reload image list if active
        log("info", message=f"Folder changed notification received")
        if self.is_active:
            log("debug", message="BrowseController/_on_notify_folder_changed_main_thread: controller active, refreshing view")
            self._reload_image_list_in_folder(updated_path=event.src_path)
            if event.event_type == 'moved':
                 log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: moved event, refreshing dest {event.dest_path}")
                 self._reload_image_list_in_folder(updated_path=event.dest_path)
        else:
            self._folder_changed_in_background.append(event.src_path)
            if event.event_type == 'moved':
                self._folder_changed_in_background.append(event.dest_path)
    
    def _try_delete_root_folder(self, event: watchdog.events.FileSystemEvent) -> QStandardItem | None:
        src_path = normalized_folder_path(event.src_path)
        log("debug", message=f"BrowseController/_try_delete_root_folder: checking deletion for {src_path}")
        if event.event_type == 'deleted':
            item = self.folder_list_model().get_containing_root_folder(src_path)
            
            item_path = ''
            if item:
                data = item.data(Qt.UserRole)
                if data:
                    item_path = normalized_folder_path(data).replace('\\', '/')
                else:
                    log("warning", message="BrowseController/_try_delete_root_folder: item found but has no user data")
            else:
                 log("debug", message=f"BrowseController/_try_delete_root_folder: no containing root folder found for {src_path}")

            log("debug", message=f"BrowseController/_try_delete_root_folder: item_path='{item_path}', src_path='{src_path}'")

            if item_path == src_path:
                log("debug", message=f"BrowseController/_try_delete_root_folder: MATCH FOUND. Deleting root folder {src_path}")
                index = self.folder_list_model().indexFromItem(item)
                self.folder_list_model().deleteFolder(index)

                if self._selected_folder_path and normalized_folder_path(self._selected_folder_path).startswith(src_path):
                    log("debug", message="BrowseController/_try_delete_root_folder: clearing selection inside deleted folder")
                    self.image_list_model().load_images_from_paths([])
                    self._selected_folder_path = ''
                return item
        return None

    def _repopulate_folder_item(self, src_path: str):
        log("debug", message=f"BrowseController/_repopulate_folder_item: source-driven tree update already covers {src_path}")

    def _on_mobile_transfer_status_poll_timeout(self) -> None:
        assert QThread.isMainThread()
        log("debug", message="BrowseController/_on_mobile_transfer_status_poll_timeout: refreshing mobile folder status")
        self._refresh_mobile_transfer_states()

    def on_active_change(self, old_value: bool, new_value: bool):
        if new_value:
            self._refresh_mobile_transfer_states()
            self._mobile_transfer_status_timer.start()
        else:
            self._mobile_transfer_status_timer.stop()
        if new_value and self._folder_changed_in_background:
            self._reload_image_list_in_folder()
            self._folder_changed_in_background = []

    def _reload_image_list_in_folder(self, updated_path: str = None):
        log("debug", message=f"BrowseController/_reload_image_list_in_folder: updated_path={updated_path}, selected={self._selected_folder_path}")
        if not self._selected_folder_path:
            log("debug", message="BrowseController/_reload_image_list_in_folder: no folder selected, skipping")
            return
        # if updated_path is not None but updated_path is not under folder_path, ignore
        if updated_path:
            try:
                if not Path(updated_path).resolve().is_relative_to(Path(self._selected_folder_path).resolve()):
                    log("debug", message=f"BrowseController/_reload_image_list_in_folder: {updated_path} is not relative to {self._selected_folder_path}, skipping")
                    return
            except ValueError as e:
                log("warning", message=f"BrowseController/_reload_image_list_in_folder: path resolution error: {e}")
                return
        
        log("debug", message=f"BrowseController/_reload_image_list_in_folder: loading images from {self._selected_folder_path}")
        folders_changed = [p for p in self._folder_changed_in_background]
        if updated_path:
            folders_changed.append(updated_path)
        self._folder_changed_in_background = []
        for p in folders_changed:
            if normalized_folder_path(p).replace('\\', '/').startswith(normalized_folder_path(self._selected_folder_path).replace('\\', '/')):
                self.image_list_model().load_images_from_folder(self._selected_folder_path)
                break

    def _refresh_mobile_transfer_states(self) -> None:
        with create_db_conn(ctx=self.ctx) as conn:
            persisted_states_by_path = get_mobile_folder_transfer_states(conn)
            summaries_by_path = get_mobile_folder_summaries_by_path(conn)
        mobile_folder_paths = {
            normalized_folder_path(path).replace('\\', '/')
            for path in persisted_states_by_path.keys()
        }
        transferring_states_by_path = {
            path: state
            for path, state in persisted_states_by_path.items()
            if normalized_folder_path(path).replace('\\', '/') in mobile_folder_paths
            and state == MOBILE_TRANSFER_STATE_TRANSFERRING
        }

        self.folder_list_model().set_mobile_folder_paths(mobile_folder_paths)
        self.folder_list_model().set_mobile_transfer_states(transferring_states_by_path)
        self.folder_list_model().set_mobile_folder_summaries(summaries_by_path)
