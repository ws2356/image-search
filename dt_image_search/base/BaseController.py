from PySide6.QtCore import QAbstractListModel, QAbstractItemModel, Qt, QObject
from dt_image_search.view.dts_image_viewer import ImageViewerDialog
from dt_image_search.view.image_navigator import ModelBasedNavigator
from dt_image_search.base.image_list_model import ImageListModel
from dt_image_search.base.FolderTreeModel import FolderTreeModel

class BaseController:
    def __init__(self):
        self._is_active = False
    # A read-write property that corresponds to whether the controller is in active state.
    @property
    def is_active(self) -> bool:
        return self._is_active  # Default implementation, can be overridden by subclasses

    @is_active.setter
    def is_active(self, value: bool):
        _old_value = self._is_active
        self._is_active = value
        self.on_active_change(_old_value, value)

    def folder_list_model(self) -> FolderTreeModel:
        pass

    def image_list_model(self) -> ImageListModel:
        pass

    def on_folder_added(self, folder_path: str):
        pass

    def on_search_query(self, query: str):
        pass
    
    def on_folder_selected(self, row: int):
        pass

    def on_image_double_clicked(self, index):
        image_path = index.data(Qt.UserRole)  # or your role
        if image_path:
            # Create a navigator based on the current image list model
            navigator = self.create_image_navigator(index.row())
            viewer = ImageViewerDialog(image_path, navigator=navigator)
            viewer.exec()
    
    def create_image_navigator(self, initial_index: int):
        """Create an appropriate navigator for the given initial index.
        
        Subclasses can override this to provide different navigation strategies.
        """
        return ModelBasedNavigator(self.image_list_model(), initial_index)
    
    def on_active_change(self, old_value: bool, new_value: bool):
        pass