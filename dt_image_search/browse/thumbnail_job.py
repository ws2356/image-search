import logging
import threading
from PySide6.QtCore import QRunnable, Signal, QObject, Qt
from PySide6.QtGui import QPixmap, QIcon, QImage

class ThumbnailJobSignals(QObject):
    finished = Signal(int, QImage)  # row index and icon

class ThumbnailJob(QRunnable):
    def __init__(self, row, path, icon_size, signal_target):
        super().__init__()
        self.row = row
        self.path = path
        self.icon_size = icon_size
        self.signals = signal_target

    def run(self):
        image = QImage(self.path).scaled(
            self.icon_size.width(), self.icon_size.height(),
            Qt.KeepAspectRatio, Qt.SmoothTransformation
        )
        thread = threading.current_thread()
        logging.info(f"Thumbnail created [{thread.name} - {thread.ident}]: {self.row} - {self.path}")
        self.signals.finished.emit(self.row, image)
