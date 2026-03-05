import watchdog
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, QPersistentModelIndex, Qt, QModelIndex, Signal, QObject, QThread
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.browse.fs_image_list_model import FSImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.dts_db import create_db_conn, insert_folder, match_parent_folder, get_all_folders
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.index.dts_index import index_path_for_folder, delete_folder
from dt_image_search.tools.dts_debounce import debounce
from dt_image_search.index.index_worker import add_index_worker
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.fs.bm_fs_monitor import add_folder, remove_folder
from dt_image_search.bm_context import BMContext
from dt_image_search.tools.dts_util import normalized_folder_path
from dt_image_search.tools.dts_event_bus import default_bus

class BrowseController(BaseController):
    class FSChangedSignal(QObject):
        signal = Signal(watchdog.events.FileSystemEvent)

    class FolderSelectionSignal(QObject):
        select_folder = Signal(QStandardItem)  # Signal to request folder selection in UI

    def __init__(self, ctx: BMContext):
        super().__init__()
        self.folderListModel = None
        self.ctx = ctx
        self.imageListModel = None
        self._init_folders()
        self._fs_changed = False
        self._fs_changed_signal = self.FSChangedSignal()
        self._fs_changed_signal.signal.connect(self._on_notify_folder_changed_main_thread)
        self._folder_selection_signal = self.FolderSelectionSignal()
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
        with create_db_conn(ctx=self.ctx) as conn:
            parent_folder = match_parent_folder(conn, folder_path)
            if parent_folder:
                log("debug", message=f"BrowseController/on_folder_added: found parent folder {parent_folder.path}")
                # Auto-select the newly added folder in the UI
                folder_item = self.folder_list_model().get_containing_root_folder(parent_folder.path)
                if folder_item:
                    log("debug", message=f"BrowseController/on_folder_added: emitting select_folder for parent item {parent_folder.path}")
                    self._folder_selection_signal.select_folder.emit(folder_item)
                else:
                     log("warning", message=f"BrowseController/on_folder_added: parent folder item not found in model for {parent_folder.path}")
                return

            folder = insert_folder(conn, folder_path)
            if not folder:
                log("error", message=f"BrowseController/on_folder_added: failed to insert folder {folder_path} into DB")
                return
            log("debug", message=f"BrowseController/on_folder_added: inserted folder {folder.path} into DB with ID {folder.id}")
            self.folder_list_model().add_root_folder([folder.path])
            log("debug", message=f"BrowseController/on_folder_added: added root folder to model: {folder.path}")

            log("info", message=f"Inserted folder with ID: {folder.id}")
            add_index_worker(ctx=self.ctx, folder=folder)
            log("debug", message=f"BrowseController/on_folder_added: added index worker for {folder.path}")
            add_folder(folder.path)
            log("debug", message=f"BrowseController/on_folder_added: added folder to FS monitor: {folder.path}")
        # Auto-select the newly added root folder
        folder_item = self.folder_list_model().get_containing_root_folder(folder_path)
        if folder_item:
            log("debug", message=f"BrowseController/on_folder_added: emitting select_folder for new item {folder_path}")
            self._folder_selection_signal.select_folder.emit(folder_item)
        else:
            log("warning", message=f"BrowseController/on_folder_added: new folder item not found in model for {folder_path}")

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
        _root_folders = self._load_folders()
        self.folder_list_model().add_root_folder(_root_folders)

    def _load_folders(self) -> list[str]:
        with create_db_conn(ctx=self.ctx) as conn:
            folders = get_all_folders(conn)
            # sort folders asc
            folders.sort(key=lambda f: f.path)
            root_folders = []
            for item in folders:
                if len(root_folders) and item.path.startswith(root_folders[-1]):
                    continue
                root_folders.append(item.path)
            log("info", message=f"Loaded {len(root_folders)} root folders from the database.")
            return root_folders

    def _create_model_for_folder(self) -> QAbstractItemModel:
        model = FolderTreeModel()
        return model
    
    @debounce(3)  # Debounce search queries to avoid excessive calls
    def _on_notify_folder_changed(self, event):
        log("debug", message=f"BrowseController/_on_notify_folder_changed: event type={event.event_type}, src={event.src_path}")
        self._fs_changed_signal.signal.emit(event)

    def _on_notify_folder_changed_main_thread(self, event):
        # Assert main thread
        assert QThread.isMainThread()
        log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: processing event {event.event_type} for {event.src_path}")
        deleted_item = self._try_delete_root_folder(event) if event.event_type == 'deleted' else None
        if not deleted_item:
            log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: not a root deletion, repopulating {event.src_path}")
            self._repopulate_folder_item(event.src_path)
        else:
             log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: root folder deleted: {event.src_path}")

        # reload image list if active
        log("info", message=f"Folder changed notification received")
        if self.is_active:
            log("debug", message="BrowseController/_on_notify_folder_changed_main_thread: controller active, refreshing view")
            self._folder_change_impl(updated_path=event.src_path)
            if event.event_type == 'moved':
                 log("debug", message=f"BrowseController/_on_notify_folder_changed_main_thread: moved event, refreshing dest {event.dest_path}")
                 self._folder_change_impl(updated_path=event.dest_path)
        else:
            log("debug", message="BrowseController/_on_notify_folder_changed_main_thread: controller inactive, setting _fs_changed=True")
            self._fs_changed = True
    
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
        log("debug", message=f"BrowseController/_repopulate_folder_item: repopulating {src_path}")
        affected_root_item = self.folder_list_model().get_containing_root_folder(src_path)
        if affected_root_item:
             log("debug", message=f"BrowseController/_repopulate_folder_item: found affected root item {affected_root_item.data(Qt.UserRole)}")
             self.folder_list_model().repopulate_folder_item(src_path)
             
             # Safely get data from item
             data = affected_root_item.data(Qt.UserRole)
             if data:
                 self._selected_folder_path = data
                 log("debug", message=f"BrowseController/_repopulate_folder_item: updated selection to {self._selected_folder_path}")
             else:
                 log("warning", message="BrowseController/_repopulate_folder_item: affected root item has no data")
        else:
             log("warning", message=f"BrowseController/_repopulate_folder_item: no affected root item found for {src_path}")

    def on_active_change(self, old_value: bool, new_value: bool):
        if new_value and self._fs_changed:
            self._folder_change_impl()
            self._fs_changed = False

    def _folder_change_impl(self, updated_path: str = None):
        log("debug", message=f"BrowseController/_folder_change_impl: updated_path={updated_path}, selected={self._selected_folder_path}")
        if not self._selected_folder_path:
            log("debug", message="BrowseController/_folder_change_impl: no folder selected, skipping")
            return
        # if updated_path is not None but updated_path is not under folder_path, ignore
        if updated_path:
            try:
                if not Path(updated_path).resolve().is_relative_to(Path(self._selected_folder_path).resolve()):
                    log("debug", message=f"BrowseController/_folder_change_impl: {updated_path} is not relative to {self._selected_folder_path}, skipping")
                    return
            except ValueError as e:
                log("warning", message=f"BrowseController/_folder_change_impl: path resolution error: {e}")
                return
        
        log("debug", message=f"BrowseController/_folder_change_impl: loading images from {self._selected_folder_path}")
        self.image_list_model().load_images_from_folder(self._selected_folder_path)