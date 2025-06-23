from importlib.metadata import files
import logging
import os
import threading
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize
from PySide6.QtGui import QPixmap, QIcon, QImage
from dt_image_search.browse.thumbnail_job import ThumbnailJob, ThumbnailJobSignals

class ImageListModel(QAbstractListModel):
    def __init__(self, image_paths=None, parent=None):
        super().__init__(parent)
        self.image_paths = image_paths or []
        self.thumbnail_cache = {}
        self.placeholder_icon = QIcon(QPixmap(150, 150))  # empty gray or icon
        self.thread_pool = QThreadPool.globalInstance()
        self.loading_paths = set()

    def rowCount(self, parent=QModelIndex()):
        return len(self.image_paths)

    def data(self, index, role):
        if not index.isValid():
            return None
        path = self.image_paths[index.row()]

        if role == Qt.DecorationRole:
            if path in self.thumbnail_cache:
                return self.thumbnail_cache[path]

            if path not in self.loading_paths:
                self.loading_paths.add(path)
                # Start async thumbnail job
                signals = ThumbnailJobSignals()
                signals.finished.connect(self._on_thumbnail_ready)
                job = ThumbnailJob(index.row(), path, QSize(150, 150), signals)
                self.thread_pool.start(job)

            return self.placeholder_icon

        if role == Qt.ToolTipRole:
            return os.path.basename(path)

        return None

    def load_images_from_paths(self, paths):
        self.beginResetModel()
        self.image_paths = paths
        self.thumbnail_cache.clear()
        self.endResetModel()

    def _on_thumbnail_ready(self, row, image):
        path = self.image_paths[row]
        self.loading_paths.discard(path)
        self.thumbnail_cache[path] = QPixmap.fromImage(image)
        index = self.index(row)

        self.dataChanged.emit(index, index, [Qt.DecorationRole])