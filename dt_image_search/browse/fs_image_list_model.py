import os

from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal

from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.index.dts_index import is_image_file
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_util import back_slash_to_forward_slash


class FolderImageLoadSignals(QObject):
    finished = Signal(str, int, object)


class FolderImageLoadJob(QRunnable):
    def __init__(self, folder: str, request_id: int, signal_target: FolderImageLoadSignals):
        super().__init__()
        self.folder = folder
        self.request_id = request_id
        self.signals = signal_target

    def run(self) -> None:
        image_paths: list[str] = []
        try:
            image_paths = sorted(
                [
                    back_slash_to_forward_slash(os.path.join(self.folder, entry_name))
                    for entry_name in os.listdir(self.folder)
                    if is_image_file(entry_name)
                ]
            )
        except Exception as exc:
            log("error", message=f"FSImageListModel/FolderImageLoadJob: failed to list {self.folder}: {exc}")
        finally:
            self.signals.finished.emit(self.folder, self.request_id, image_paths)


class FSImageListModel(ImageListModel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._folder_load_request_id = 0
        self._requested_folder_path = ""
        self._folder_load_signals = FolderImageLoadSignals()
        self._folder_load_signals.finished.connect(self._on_folder_images_loaded)
        self._folder_load_thread_pool = QThreadPool(self)
        self._folder_load_thread_pool.setMaxThreadCount(1)

    def load_images_from_folder(self, folder: str) -> None:
        log("info", message=f"Loading images from folder: {folder}")
        self._requested_folder_path = folder
        self._folder_load_request_id += 1
        self._folder_load_thread_pool.start(
            FolderImageLoadJob(folder, self._folder_load_request_id, self._folder_load_signals)
        )

    def _on_folder_images_loaded(self, folder: str, request_id: int, image_paths: list[str]) -> None:
        if request_id != self._folder_load_request_id:
            return
        if folder != self._requested_folder_path:
            return
        self.load_images_from_paths(image_paths)
