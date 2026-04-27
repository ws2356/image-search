import threading
from PySide6.QtCore import QRunnable, Signal, QObject
from PySide6.QtGui import QImage
from dt_image_search.telemetry.telemetry_client import log
from PIL import Image

from dt_image_search.pil_image_support import open_pil_image


class ThumbnailJobSignals(QObject):
    finished = Signal(str, QImage)  # path and icon


class ThumbnailJob(QRunnable):
    def __init__(self, path: str, icon_size, device_pixel_ratio: float, signal_target):
        super().__init__()
        self.path = path
        self.icon_size = icon_size
        self.device_pixel_ratio = device_pixel_ratio
        self.signals = signal_target

    # @with_trace("ThumbnailJob.run")
    def run(self) -> None:
        image = QImage()
        try:
            target_size = (self.icon_size.width(), self.icon_size.height())
            with open_pil_image(self.path) as pil_image:
                # Hint decoders (e.g. JPEG) to avoid full-resolution decode when possible.
                try:
                    pil_image.draft("RGBA", target_size)
                except Exception:
                    pass
                pil_image = pil_image.convert("RGBA")
                pil_image.thumbnail(target_size, Image.Resampling.LANCZOS)
                data = pil_image.tobytes("raw", "RGBA")
                image = QImage(data, pil_image.width, pil_image.height, QImage.Format_RGBA8888).copy()
                image.setDevicePixelRatio(max(1.0, self.device_pixel_ratio))

            if not image or image.isNull():
                log("error", "image_thumbnail", f"Failed to create thumbnail for {self.path}", __file__)
            thread = threading.current_thread()
            log("debug", message=f"Thumbnail created [{thread.name} - {thread.ident}]: {self.path}")
        except Exception as e:
            log("error", "image_thumbnail", f"Error creating thumbnail for {self.path}: {e}", __file__)
        finally:
            self.signals.finished.emit(self.path, image)
