import logging
import threading
from PySide6.QtCore import QRunnable, Signal, QObject, Qt
from PySide6.QtGui import QPixmap, QIcon, QImage
from dt_image_search.telemetry.telemetry_client import with_trace, log

class ThumbnailJobSignals(QObject):
    finished = Signal(str, QImage)  # path and icon

class ThumbnailJob(QRunnable):
    def __init__(self, path, icon_size, signal_target):
        super().__init__()
        self.path = path
        self.icon_size = icon_size
        self.signals = signal_target

    # @with_trace("ThumbnailJob.run")
    def run(self):
        image = QImage(self.path).scaled(
            self.icon_size.width(), self.icon_size.height(),
            Qt.KeepAspectRatio, Qt.SmoothTransformation
        )
        if not image or image.isNull():
            log("error", "image_thumbnail", f"Failed to create thumbnail for {self.path}", __file__)
        thread = threading.current_thread()
        log("info", message= f"Thumbnail created [{thread.name} - {thread.ident}]: {self.path}")
        self.signals.finished.emit(self.path, image)
