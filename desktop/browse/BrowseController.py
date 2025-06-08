from base.BaseController import BaseController
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize
from .image_list_model import ImageListModel

class BrowseController(BaseController):
    def __init__(self):
        super().__init__()
        self.model = None

    def folder_list_model(self) -> QAbstractListModel:
        pass

    def image_list_model(self) -> QAbstractListModel:
        if self.model is None:
          self.model = ImageListModel()
        return self.model

    def on_folder_added(self, folder_path: str):
        self.model.load_images_from_folder(folder_path)

    def on_folder_selected(self, row: int):
        pass