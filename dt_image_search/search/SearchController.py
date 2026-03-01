import logging
import os
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex, QTimer
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.dts_db import create_db_conn, get_all_folders
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.index.dts_index import query_index, index_path_for_folder, TOP_K
from dt_image_search.tools.dts_debounce import debounce
from dt_image_search.tools.dts_perf import perffunc as profile
from dt_image_search.tools.dts_dispatcher import dispatcher
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.bm_context import BMContext
from dt_image_search.base.status_bar_messenger import status_bar_messenger

class SearchController(BaseController):
    def __init__(self, ctx: BMContext):
        super().__init__()
        self.imageListModel = None
        self.ctx = ctx

    def folder_list_model(self) -> FolderTreeModel:
        raise NotImplementedError("SearchController does not implement folder_list_model")

    def image_list_model(self) -> ImageListModel:
        if self.imageListModel is None:
          self.imageListModel = ImageListModel()
        return self.imageListModel

    # Override setter for is_active to reset the image list model
    @BaseController.is_active.setter
    def is_active(self, value: bool):
        BaseController.is_active.fset(self, value)
        if not value:
            self.imageListModel.on_detach()

    @debounce(1)  # Debounce search queries to avoid excessive calls
    @profile
    def on_search_query(self, query: str):
        if not self.is_active:
            return

        log("info", message=f"Search query: {query}")
        status_bar_messenger.show_status_message.emit(f"Searching for: {query}")
        # TODO: do this in async job which can be cancelled
        dispatcher.post(lambda: self.imageListModel.load_images_from_paths([]))

        results = []
        with create_db_conn(ctx=self.ctx) as conn:
            folders = get_all_folders(conn)
            for folder in folders:
                results_in_folder = self._search_in_folder(folder, query)
                if results_in_folder:
                    dispatcher.post(lambda res=results_in_folder[0]: self.imageListModel.add_image(res))
                for item in results_in_folder:
                    log("debug", message=f"Found item: {item[0]} with score: {item[1]}")
                results.extend(results_in_folder)
                results = sorted(results, key=lambda x: x[1], reverse=True)[:TOP_K]
        if not results:
            log("info", message="No results found for the search query")
        status_bar_messenger.show_status_message.emit(f"Search completed with {len(results)} results.")
        dispatcher.post(lambda: self.imageListModel.load_images(results))
    
    @profile
    def _search_in_folder(self, folder: Folder, query: str):
        log("info", message=f"Searching in folder: {folder.path}")
        # Implement the search logic here
        # This could involve querying a database or filtering files in the folder
        index_path = index_path_for_folder(ctx=self.ctx, folder=folder)
        if not Path(index_path).exists():
            log("warning", "search", message=f"Index file does not exist for folder: {folder.path}")
            return []
        return query_index(ctx=self.ctx, folder_id=folder.id, index_path=index_path, query_text=query)