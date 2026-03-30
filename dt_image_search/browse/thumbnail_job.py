import threading
from PySide6.QtCore import QRunnable, Signal, QObject, Qt
from PySide6.QtGui import QImage
from dt_image_search.telemetry.telemetry_client import log
from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = True
Image.MAX_IMAGE_PIXELS = None

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
        image = QImage()
        try:
            target_size = (self.icon_size.width(), self.icon_size.height())
            with Image.open(self.path) as pil_image:
                # Hint decoders (e.g. JPEG) to avoid full-resolution decode when possible.
                try:
                    pil_image.draft("RGBA", target_size)
                except Exception:
                    pass
                pil_image = pil_image.convert("RGBA")
                pil_image.thumbnail(target_size, Image.Resampling.LANCZOS)
                data = pil_image.tobytes("raw", "RGBA")
                image = QImage(data, pil_image.width, pil_image.height, QImage.Format_RGBA8888).copy()

            if not image or image.isNull():
                log("error", "image_thumbnail", f"Failed to create thumbnail for {self.path}", __file__)
            thread = threading.current_thread()
            log("debug", message= f"Thumbnail created [{thread.name} - {thread.ident}]: {self.path}")
        except Exception as e:
            log("error", "image_thumbnail", f"Error creating thumbnail for {self.path}: {e}", __file__)
        finally:
            self.signals.finished.emit(self.path, image)
