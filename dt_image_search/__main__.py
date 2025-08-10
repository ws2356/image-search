import os
import sys

# Add the parent directory of this file (i.e. the one that contains dt_image_search/)
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView, QMenu
from PySide6.QtGui import QPixmap
from PySide6.QtCore import QCoreApplication, Qt, QModelIndex, QSize

from dt_image_search.view.dts_mainwindow_ui import Ui_MainWindow
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.search.SearchController import SearchController
from dt_image_search.index.dts_index import init as index_init
from dt_image_search.index.index_worker import resume_index_workers
from dt_image_search.telemetry.telemetry_client import flush_telemetry

from dt_image_search.model.dts_config import get_debugpy_port
import debugpy
if get_debugpy_port() > 0:
    debugpy.listen(("0.0.0.0", get_debugpy_port()))
    print(f"Waiting for debugger attach @ {get_debugpy_port()}")
    debugpy.wait_for_client()


os.environ['KMP_DUPLICATE_LIB_OK'] = 'true'

_BrowseMode = 1
_SearchMode = 2

index_init()  # Initialize the index system
resume_index_workers()  # Resume workers to continue indexing after app start

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        self._alternativeController = None
        self._mode = _BrowseMode

        self.controller = BrowseController()
        self.controller.is_active = True  # Set the controller to active state

        self.ui.addFolderButton.clicked.connect(self.on_add_folder_button_click)
        self.ui.folderTreeView.setModel(self.controller.folder_list_model())
        self.ui.folderTreeView.selectionModel().currentChanged.connect(self.controller.on_folder_selected)
        self.ui.folderTreeView.expanded.connect(self.controller.on_item_expanded)
        self.ui.folderTreeView.setContextMenuPolicy(Qt.CustomContextMenu)
        self.ui.folderTreeView.customContextMenuRequested.connect(self.show_tree_context_menu)

        self.image_list_view.doubleClicked.connect(self.controller.on_image_double_clicked)

        self.image_list_view.setModel(self.controller.image_list_model())

        self.ui.searchInput.textChanged.connect(self.handle_search)
        self.ui.searchInput.setClearButtonEnabled(True)

        for view in [self.ui.searchImageListView, self.ui.browseImageListView]:
            view.setEditTriggers(QAbstractItemView.NoEditTriggers)
            view.setDragEnabled(False)
            view.setAcceptDrops(False)
            view.setDropIndicatorShown(False)
            view.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

            view.setViewMode(QListView.IconMode)
            view.setResizeMode(QListView.Adjust)
            view.setUniformItemSizes(True)
            view.setIconSize(QSize(150, 150))
            view.setSpacing(10)
            view.setSelectionMode(QAbstractItemView.NoSelection)

    @property
    def image_list_view(self):
        if self._mode == _SearchMode:
            return self.ui.searchImageListView
        elif self._mode == _BrowseMode:
            return self.ui.browseImageListView

    def on_add_folder_button_click(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
        if not folder:
            return
        self.controller.on_folder_added(folder)
        # index = self.controller.get_index_for_folder(folder)
        # if index.isValid():
        #     self.ui.folderList.setCurrentIndex(index)
        #     self.ui.folderList.scrollTo(index)
    
    def handle_search(self, query):
        query = query.strip()
        tmp_controller = self._alternativeController
        if query:
            if self._mode != _SearchMode:
                self.image_list_view.doubleClicked.disconnect(self.controller.on_image_double_clicked)

                self._mode = _SearchMode
                self._alternativeController = self.controller
                self.controller = tmp_controller or SearchController()
                self._alternativeController.is_active = False  # Deactivate the alternative controller
                self.controller.is_active = True
                self.image_list_view.setModel(self.controller.image_list_model())
                self.ui.mainStack.setCurrentWidget(self.ui.searchPage)
                # Update layout
                self.ui.browsePage.layout().removeWidget(self.ui.searchInput)
                self.ui.searchPage.layout().insertWidget(0, self.ui.searchInput)
                self.ui.searchInput.setFocus()

                self.image_list_view.doubleClicked.connect(self.controller.on_image_double_clicked)
            self.controller.on_search_query(query)
        else:
            if self._mode != _BrowseMode:
                self.image_list_view.doubleClicked.disconnect(self.controller.on_image_double_clicked)

                self._mode = _BrowseMode
                self._alternativeController = self.controller
                self.controller = tmp_controller or BrowseController()
                self._alternativeController.is_active = False  # Deactivate the alternative controller
                self.controller.is_active = True
                self.image_list_view.setModel(self.controller.image_list_model())
                self.ui.mainStack.setCurrentWidget(self.ui.browsePage)
                # Update layout
                self.ui.searchPage.layout().removeWidget(self.ui.searchInput)
                self.ui.browseLeftPanel.layout().insertWidget(0, self.ui.searchInput)
                self.ui.searchInput.setFocus()
                self.image_list_view.doubleClicked.connect(self.controller.on_image_double_clicked)
        

    def show_tree_context_menu(self, pos):
        index = self.ui.folderTreeView.indexAt(pos)
        item = self.ui.folderTreeView.model().itemFromIndex(index)
        is_root_folder = item and not item.parent()
        if not is_root_folder:
            return
        folder_path = item.data(Qt.UserRole) if item else None
        menu = QMenu(self)
        remove_action = menu.addAction("Remove Folder")
        if menu.exec(self.ui.folderTreeView.mapToGlobal(pos)) == remove_action:
            self.controller.on_delete_folder(item, folder_path, is_root_folder)
            searchController = self._alternativeController or SearchController()
            searchController.on_delete_folder(item, folder_path, is_root_folder)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    QCoreApplication.instance().aboutToQuit.connect(flush_telemetry)
    window.show()
    sys.exit(app.exec())
