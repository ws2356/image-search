import os
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex
from PySide6.QtGui import QPixmap, QIcon

class ImageListModel(QAbstractListModel):
    def __init__(self, image_paths=None, parent=None):
        super().__init__(parent)
        self.image_paths = image_paths or []
        self.thumbnail_cache = {}

    def rowCount(self, parent=QModelIndex()):
        return len(self.image_paths)

    def data(self, index, role):
        if not index.isValid():
            return None
        path = self.image_paths[index.row()]

        if role == Qt.DecorationRole:
            if path not in self.thumbnail_cache:
                pixmap = QPixmap(path).scaled(150, 150, Qt.KeepAspectRatio, Qt.SmoothTransformation)
                self.thumbnail_cache[path] = QIcon(pixmap)
            return self.thumbnail_cache[path]

        if role == Qt.ToolTipRole:
            return os.path.basename(path)

        return None

    def load_images_from_folder(self, folder):
        image_exts = (".jpg", ".jpeg", ".png", ".bmp", ".gif")
        files = [os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith(image_exts)]
        self.beginResetModel()
        self.image_paths = files
        self.thumbnail_cache.clear()
        self.endResetModel()