from importlib.metadata import files
import logging
import os
import threading
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QThreadPool, QSize
from PySide6.QtGui import QPixmap, QIcon, QImage
from dt_image_search.browse.thumbnail_job import ThumbnailJob, ThumbnailJobSignals
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.index.dts_index import is_image_file
from dt_image_search.telemetry.telemetry_client import log

class FSImageListModel(ImageListModel):
    def __init__(self, parent=None):
        super().__init__(parent)

    def load_images_from_folder(self, folder):
        log("info", message=f"Loading images from folder: {folder}")
        files = [os.path.join(folder, f) for f in os.listdir(folder) if is_image_file(f)]
        self.load_images_from_paths(files)
    