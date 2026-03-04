import os
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex
from dt_image_search.telemetry.telemetry_client import log

class FolderListModel(QAbstractListModel):
    def __init__(self, folder_paths: list[str]):
        super().__init__()
        self.folders = folder_paths
        log("debug", message=f"folder_list_model/__init__: initialized with {len(folder_paths)} folders")

    def rowCount(self, parent=QModelIndex()):
        return len(self.folders)

    def data(self, index, role):
        if role == Qt.DisplayRole:
            return os.path.basename(self.folders[index.row()])
        if role == Qt.ToolTipRole:
            return self.folders[index.row()]
