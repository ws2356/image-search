import logging
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.db import create_db_conn, insert_folder, match_child_folders, match_parent_folder, get_all_folders, remove_folders
from dt_image_search.base.FolderTreeModel import FolderTreeModel

class SearchController(BaseController):
    def __init__(self):
        super().__init__()
        self.imageListModel = None

    def folder_list_model(self) -> QAbstractItemModel:
        raise NotImplementedError("SearchController does not implement folder_list_model")

    def image_list_model(self) -> QAbstractListModel:
        if self.imageListModel is None:
          self.imageListModel = ImageListModel()
        return self.imageListModel

    def on_search_query(self, query: str):
        logging.info(f"Search query: {query}")