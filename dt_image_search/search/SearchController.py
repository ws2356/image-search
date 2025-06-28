import logging
from datetime import datetime
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex, QTimer
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.db import create_db_conn, insert_folder, match_child_folders, match_parent_folder, get_all_folders, remove_folders
from dt_image_search.model.folder import Folder
from dt_image_search.model.fs import get_app_data_path
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.index.index import query_index, index_path_for_folder, build_index
from dt_image_search.tools.debounce import debounce
from dt_image_search.tools.perf import perffunc as profile
from dt_image_search.tools.dispatcher import dispatcher

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

    @debounce(3)  # Debounce search queries to avoid excessive calls
    @profile
    def on_search_query(self, query: str):
        if not self.is_active:
            return

        logging.info(f"Search query: {query}")
        # TODO: do this in async job which can be cancelled
        results = []
        with create_db_conn() as conn:
            folders = get_all_folders(conn)
            for folder in folders:
                results.extend(self._search_in_folder(folder, query))
                dispatcher.post(lambda: self.imageListModel.load_images_from_paths(results))
        if not results:
            logging.info("No results found for the search query")
    
    @profile
    def _search_in_folder(self, folder: Folder, query: str):
        logging.info(f"Searching in folder: {folder.path} with query: {query}")
        # Implement the search logic here
        # This could involve querying a database or filtering files in the folder
        index_path = index_path_for_folder(folder)
        if not Path(index_path).exists():
            logging.warning(f"Index file does not exist for folder: {folder.path}")
            return []
        return query_index(index_path, query)