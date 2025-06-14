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

    def get_index_for_folder(self, folder_path: str) -> QModelIndex:
        model = self.folder_list_model()
        for row in range(model.rowCount()):
            if model.data(model.index(row), Qt.ToolTipRole) == folder_path:
                return model.index(row)
        return QModelIndex()
