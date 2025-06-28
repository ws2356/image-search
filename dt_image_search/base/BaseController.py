from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QModelIndex, QThreadPool, QSize

class BaseController:
    def __init__(self):
        self._is_active = False
    # A read-write property that corresponds to whether the controller is in active state.
    @property
    def is_active(self) -> bool:
        return self._is_active  # Default implementation, can be overridden by subclasses

    @is_active.setter
    def is_active(self, value: bool):
        self._is_active = value

    def folder_list_model(self) -> QAbstractItemModel:
        pass

    def image_list_model(self) -> QAbstractListModel:
        pass

    def on_folder_added(self, folder_path: str):
        pass

    def on_search_query(self, query: str):
        pass
    
    def on_folder_selected(self, row: int):
        pass