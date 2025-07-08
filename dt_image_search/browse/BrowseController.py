import logging
import os
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.browse.fs_image_list_model import FSImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.dts_db import create_db_conn, insert_folder, match_child_folders, match_parent_folder, get_all_folders, insert_file
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.index.dts_index import index_path_for_folder, build_index, supported_image_types
from dt_image_search.model.dts_folder import Folder
from dt_image_search.index.index_worker import add_index_worker

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
            # TODO: remove clip_index files
            # child_folders = match_child_folders(conn, folder_path)
            # if child_folders:
                # remove_folders(conn, child_folders)
            folder = insert_folder(conn, folder_path)
            logging.info(f"Inserted folder with ID: {folder.id}")
            self.folder_list_model().add_root_folder([folder_path])
            add_index_worker(folder, replace_existing=True)

    def on_folder_selected(self, current: QModelIndex, previous: QModelIndex):
        folder_path = current.data(Qt.UserRole)
        logging.info(f"on_folder_selected: {folder_path}")
        self.image_list_model().load_images_from_folder(folder_path)

    def on_item_expanded(self, index: QModelIndex):
        self.folder_list_model().expand_subfolders(index)

    def on_delete_folder(self, item: QStandardItem):
        if not item or item.parent():
            return
        folder_path = item.data(Qt.UserRole)
        self.folder_list_model().indexForItem(item)
        logging.info(f"Removing folder: {folder_path}")
        index = self.folder_list_model().indexForItem(item)
        self.folder_list_model().deleteFolder(index)

    def _init_folders(self):
        with create_db_conn() as conn:
            folders = get_all_folders(conn)
            logging.info(f"Loaded {len(folders)} folders from the database.")
            self.folder_list_model().add_root_folder([folder.path for folder in folders])

    def _create_model_for_folder(self) -> QAbstractItemModel:
        model = FolderTreeModel()
        return model