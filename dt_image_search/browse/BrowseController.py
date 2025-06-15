import logging
from dt_image_search.base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize
from dt_image_search.browse.image_list_model import ImageListModel
from dt_image_search.browse.folder_list_model import FolderListModel
from dt_image_search.model.db import create_db_conn, insert_folder, get_all_folders, get_files_for_folder

class BrowseController(BaseController):
    def __init__(self):
        super().__init__()
        self.folderListModel = None
        self.imageListModel = None

    def folder_list_model(self) -> QAbstractListModel:
        if self.folderListModel is None:
            self.folderListModel = FolderListModel([])
        return self.folderListModel

    def image_list_model(self) -> QAbstractListModel:
        if self.imageListModel is None:
          self.imageListModel = ImageListModel()
        return self.imageListModel

    def on_folder_added(self, folder_path: str):
        if folder_path not in self.folder_list_model().folders:
            logging.info(f"on_folder_added: {folder_path}")
            self.folderListModel.folders.append(folder_path)
            self.folderListModel.layoutChanged.emit()
            with create_db_conn() as conn:
                folder_id = insert_folder(conn, folder_path)
                logging.info(f"Inserted folder with ID: {folder_id}")

    def on_folder_selected(self, row: int):
        folder_path = self.folder_list_model().folders[row]
        logging.info(f"on_folder_selected: {folder_path}")
        self.image_list_model().load_images_from_folder(folder_path)

    def get_index_for_folder(self, folder_path: str) -> QModelIndex:
        model = self.folder_list_model()
        for row in range(model.rowCount()):
            if model.data(model.index(row), Qt.ToolTipRole) == folder_path:
                return model.index(row)
        return QModelIndex()