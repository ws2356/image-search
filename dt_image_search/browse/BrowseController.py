import os
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.browse.fs_image_list_model import FSImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.dts_db import create_db_conn, insert_folder, match_parent_folder, get_all_folders, get_subfolders
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.index.dts_index import index_path_for_folder, delete_folder
from dt_image_search.model.dts_folder import Folder
from dt_image_search.index.index_worker import add_index_worker
from dt_image_search.telemetry.telemetry_client import log

class BrowseController(BaseController):
    def __init__(self):
        super().__init__()
        self.folderListModel = None
        self.imageListModel = None
        self._init_folders()

    def folder_list_model(self) -> QAbstractItemModel:
        if self.folderListModel is None:
            self.folderListModel = self._create_model_for_folder()
        return self.folderListModel

    def image_list_model(self) -> QAbstractListModel:
        if self.imageListModel is None:
          self.imageListModel = FSImageListModel()
        return self.imageListModel

    def on_folder_added(self, folder_path: str):
        with create_db_conn() as conn:
            parent_folder = match_parent_folder(conn, folder_path)
            if parent_folder:
                # TODO: Select folder_path in the UI
                return
            folder = insert_folder(conn, folder_path)
            if not folder:
                return
            log("info", message=f"Inserted folder with ID: {folder.id}")
            add_index_worker(folder, replace_existing=True)
        self._reload_folders()

    def on_folder_selected(self, current: QModelIndex, previous: QModelIndex):
        folder_path = current.data(Qt.UserRole)
        log("info", message=f"on_folder_selected: {folder_path}")
        self.image_list_model().load_images_from_folder(folder_path)

    def on_item_expanded(self, index: QModelIndex):
        self.folder_list_model().expand_subfolders(index)

    def on_delete_folder(self, item: QStandardItem, data: str = None):
        log("info", message=f"Removing folder: {data}")
        index = self.folder_list_model().indexFromItem(item)
        self.folder_list_model().deleteFolder(index)
        delete_folder(data)

    def _init_folders(self):
        _root_folders = self._load_folders()
        self.folder_list_model().add_root_folder(_root_folders)

    def _reload_folders(self):
        self.folder_list_model().clear()
        self.folder_list_model().setHorizontalHeaderLabels(["Folders"])
        self._init_folders()

    def _load_folders(self) -> list[str]:
        with create_db_conn() as conn:
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