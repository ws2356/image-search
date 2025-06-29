import logging
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
from dt_image_search.index.index import query_index, index_path_for_folder, TOP_K
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

    # Override setter for is_active to reset the image list model
    @BaseController.is_active.setter
    def is_active(self, value: bool):
        BaseController.is_active.fset(self, value)
        if not value:
            self.imageListModel.on_detach()

    @debounce(3)  # Debounce search queries to avoid excessive calls
    @profile
    def on_search_query(self, query: str):
        if not self.is_active:
            return

        logging.info(f"Search query: {query}")
        # TODO: do this in async job which can be cancelled
        dispatcher.post(lambda: self.imageListModel.load_images_from_paths([]))

        results = []
        with create_db_conn() as conn:
            folders = get_all_folders(conn)
            for folder in folders:
                results_in_folder = self._search_in_folder(folder, query)
                if results_in_folder:
                    dispatcher.post(lambda: self.imageListModel.add_image(results_in_folder[0]))
                for item in results_in_folder:
                    logging.info(f"Found item: {item[0]} with score: {item[1]}")
                results.extend(results_in_folder)
                results = sorted(results, key=lambda x: x[1], reverse=True)[:TOP_K]
        if not results:
            logging.info("No results found for the search query")
        dispatcher.post(lambda: self.imageListModel.load_images(results))
    
    @profile
    def _search_in_folder(self, folder: Folder, query: str):
        logging.info(f"Searching in folder: {folder.path} with query: {query}")
        # Implement the search logic here
        # This could involve querying a database or filtering files in the folder
        index_path = index_path_for_folder(folder)
        if not Path(index_path).exists():
            logging.warning(f"Index file does not exist for folder: {folder.path}")
            return []
        return query_index(folder.id, index_path, query)