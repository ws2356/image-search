from importlib.metadata import files
import logging
import os
import threading
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize
from PySide6.QtGui import QPixmap, QIcon, QImage
from dt_image_search.browse.thumbnail_job import ThumbnailJob, ThumbnailJobSignals

class ImageListModel(QAbstractListModel):
    def __init__(self, parent=None):
        super().__init__(parent)
        # _item is a list of tuples (path, weight)
        # where path is the image file path and weight is an integer for sorting in descending order
        self._item = []
        self.thumbnail_cache = {}
        self.placeholder_icon = QIcon(QPixmap(150, 150))  # empty gray or icon
        self.thread_pool = QThreadPool.globalInstance()
        self.loading_paths = set()

    def rowCount(self, parent=QModelIndex()):
        return len(self._item)

    def data(self, index, role):
        if not index.isValid():
            return None
        path = self._item[index.row()][0]

        if role == Qt.DecorationRole:
            if path in self.thumbnail_cache:
                return self.thumbnail_cache[path]

            if path not in self.loading_paths:
                self.loading_paths.add(path)
                # Start async thumbnail job
                signals = ThumbnailJobSignals()
                signals.finished.connect(self._on_thumbnail_ready)
                job = ThumbnailJob(path, QSize(150, 150), signals)
                self.thread_pool.start(job)

            return self.placeholder_icon

        if role == Qt.ToolTipRole:
            return os.path.basename(path)

        if role == Qt.UserRole:
            return path

        return None

    def load_images_from_paths(self, paths):
        self.load_images([(path, 0) for path in paths])

    def load_images(self, paths_weight_pairs):
        self.beginResetModel()
        self._item = paths_weight_pairs
        self.endResetModel()
    
    def add_image(self, path_weight_pair):
        # binary search for insertion point
        path, weight = path_weight_pair
        left, right = 0, len(self._item) - 1
        while left <= right:
            mid = (left + right) // 2
            if self._item[mid][1] > weight:
                left = mid + 1
            else:
                right = mid - 1

        self.beginInsertRows(QModelIndex(), left, left)
        self._item.insert(left, path_weight_pair)
        self.endInsertRows()

    def on_detach(self):
        # Clear the thumbnail cache and loading paths when the model is detached
        self.thumbnail_cache.clear()
        self.load_images([])

    def _on_thumbnail_ready(self, path, image):
        self.loading_paths.discard(path)
        self.thumbnail_cache[path] = QPixmap.fromImage(image)
        # Find row index of the path
        row = next((i for i, item in enumerate(self._item) if item[0] == path), None)
        if row is None:
            return
        index = self.index(row)
        self.dataChanged.emit(index, index, [Qt.DecorationRole])