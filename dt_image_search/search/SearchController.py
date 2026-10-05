import logging
import os
from pathlib import Path
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex, QTimer
from PySide6.QtGui import QStandardItem
from PySide6.QtWidgets import QFileSystemModel
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.search.search_service import search_folders, ModelNotReadyError
from dt_image_search.tools.dts_debounce import debounce
from dt_image_search.tools.dts_perf import perffunc as profile
from dt_image_search.tools.dts_dispatcher import dispatcher
from pc_common.telemetry.telemetry_client import log
from dt_image_search.bm_context import BMContext
from dt_image_search.tools import status_messenger

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
        status_messenger.show(f"Searching for: {query}")
        dispatcher.post(lambda: self.imageListModel.load_images_from_paths([]))

        try:
            results = search_folders(self.ctx, query)
        except ModelNotReadyError as e:
            status_messenger.show(f"Model not ready ({e.state}). Please wait for the model to load.")
            return

        if not results:
            log("info", message="No results found for the search query")
        status_messenger.show(f"Search completed with {len(results)} results.")
        dispatcher.post(lambda: self.imageListModel.load_images(results))
