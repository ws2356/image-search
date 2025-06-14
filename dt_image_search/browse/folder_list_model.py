import os
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex

class FolderListModel(QAbstractListModel):
    def __init__(self, folder_paths: list[str]):
        super().__init__()
        self.folders = folder_paths

    def rowCount(self, parent=QModelIndex()):
        return len(self.folders)

    def data(self, index, role):
        if role == Qt.DisplayRole:
            return os.path.basename(self.folders[index.row()])
        if role == Qt.ToolTipRole:
            return self.folders[index.row()]
