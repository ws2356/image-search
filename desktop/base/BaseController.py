from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize

class BaseController:
    def folder_list_model(self) -> QAbstractListModel:
        pass

    def image_list_model(self) -> QAbstractListModel:
        pass

    def on_folder_added(self, folder_path: str):
        pass

    def on_search_query(self, query: str):
        pass
    
    def on_folder_selected(self, row: int):
        pass
