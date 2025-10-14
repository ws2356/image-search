import logging
import threading
from PySide6.QtCore import QRunnable, Signal, QObject, Qt
from PySide6.QtGui import QPixmap, QIcon, QImage
from dt_image_search.telemetry.telemetry_client import with_trace, log
from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = True

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
        image = None
        try:
            pil_image = Image.open(self.path).convert("RGBA")
            data = pil_image.tobytes("raw", "RGBA")
            image = QImage(data, pil_image.width, pil_image.height, QImage.Format_RGBA8888)
            image = image.scaled(
                self.icon_size.width(), self.icon_size.height(),
                Qt.KeepAspectRatio, Qt.SmoothTransformation
            )
            if not image or image.isNull():
                log("error", "image_thumbnail", f"Failed to create thumbnail for {self.path}", __file__)
            thread = threading.current_thread()
            log("debug", message= f"Thumbnail created [{thread.name} - {thread.ident}]: {self.path}")
        except Exception as e:
            log("error", "image_thumbnail", f"Error creating thumbnail for {self.path}: {e}", __file__)
        finally:
            self.signals.finished.emit(self.path, image)
