import watchdog
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex, Signal, QObject, QThread
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

class BrowseController(BaseController):
    class FSChangedSignal(QObject):
        signal = Signal(watchdog.events.FileSystemEvent)

    def __init__(self, ctx: BMContext):
        super().__init__()
        self.folderListModel = None
        self.ctx = ctx
        self.imageListModel = None
        self._init_folders()
        self._fs_changed = False
        self._fs_changed_signal = self.FSChangedSignal()
        self._fs_changed_signal.signal.connect(self._on_notify_folder_changed_main_thread)
        from dt_image_search.tools.dts_event_bus import default_bus
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

    def on_folder_added(self, folder_path: str):
        with create_db_conn(ctx=self.ctx) as conn:
            parent_folder = match_parent_folder(conn, folder_path)
            if parent_folder:
                # TODO: Select folder_path in the UI
                return
            folder = insert_folder(conn, folder_path)
            if not folder:
                return
            log("info", message=f"Inserted folder with ID: {folder.id}")
            add_index_worker(ctx=self.ctx, folder=folder, replace_existing=True)
            add_folder(folder.path)
        self._reload_folders()

    def on_folder_selected(self, current: QModelIndex, previous: QModelIndex):
        folder_path = current.data(Qt.UserRole)
        self._selected_folder_path = folder_path
        log("info", message=f"on_folder_selected: {folder_path}")
        self.image_list_model().load_images_from_folder(folder_path)

    def on_item_expanded(self, index: QModelIndex):
        self.folder_list_model().expand_subfolders(index)

    def on_delete_folder(self, item: QStandardItem, data: str = None):
        log("info", message=f"Removing folder: {data}")
        index = self.folder_list_model().indexFromItem(item)
        self.folder_list_model().deleteFolder(index)
        delete_folder(ctx=self.ctx, folder_path=data)
        remove_folder(data)

    def _init_folders(self):
        _root_folders = self._load_folders()
        self.folder_list_model().add_root_folder(_root_folders)

    def _reload_folders(self):
        self.folder_list_model().clear()
        self.folder_list_model().setHorizontalHeaderLabels(["Folders"])
        self._init_folders()

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
        self._fs_changed_signal.signal.emit(event)

    def _on_notify_folder_changed_main_thread(self, event):
        # Assert main thread
        assert QThread.isMainThread()
        deleted_item = self._try_delete_root_folder(event)
        if not deleted_item:
            self._fold_affected_root_folder(event.src_path)

        # reload image list if active
        log("info", message=f"Folder changed notification received")
        if self.is_active:
            self._folder_change_impl(updated_path=event.src_path)
            if event.event_type == 'moved':
                self._folder_change_impl(updated_path=event.dest_path)
        else:
            self._fs_changed = True
    
    def _try_delete_root_folder(self, event: watchdog.events.FileSystemEvent) -> QStandardItem | None:
        src_path = normalized_folder_path(event.src_path)
        if event.event_type == 'deleted':
            item = self.folder_list_model().get_containing_root_folder(src_path)
            item_path = normalized_folder_path(item.data(Qt.UserRole)).replace('\\', '/') if item else ''
            if item_path == src_path:
                index = self.folder_list_model().indexFromItem(item)
                self.folder_list_model().deleteFolder(index)

                if self._selected_folder_path and normalized_folder_path(self._selected_folder_path).startswith(src_path):
                    self.image_list_model().load_images_from_paths([])
                    self._selected_folder_path = ''
                return item

    def _fold_affected_root_folder(self, src_path: str):
        # Try to fold the root folder if event affects descendants of a root folder
        affected_root_item = self.folder_list_model().get_containing_root_folder(src_path)
        affected_root_item_path = normalized_folder_path(affected_root_item.data(Qt.UserRole)).replace('\\', '/') if affected_root_item else ''
        if affected_root_item and normalized_folder_path(self._selected_folder_path).replace('\\', '/').startswith(affected_root_item_path):
            self.folder_list_model().fold_root_folder(src_path)
            self._selected_folder_path = affected_root_item.data(Qt.UserRole)

    def on_active_change(self, old_value: bool, new_value: bool):
        if new_value and self._fs_changed:
            self._folder_change_impl()
            self._fs_changed = False

    def _folder_change_impl(self, updated_path: str = None):
        if not self._selected_folder_path:
            return
        # if updated_path is not None but updated_path is not under folder_path, ignore
        if updated_path and not Path(updated_path).resolve().is_relative_to(Path(self._selected_folder_path).resolve()):
            return
        self.image_list_model().load_images_from_folder(self._selected_folder_path)