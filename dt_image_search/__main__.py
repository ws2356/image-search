import os
import sys
import threading

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
from dt_image_search.telemetry.telemetry_client import flush_telemetry, startup_counter
from dt_image_search.tools.dts_util import normalized_folder_path

os.environ['KMP_DUPLICATE_LIB_OK'] = 'true'

_BrowseMode = 1
_SearchMode = 2


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

        self.controller.on_folder_added(normalized_folder_path(folder))
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
            self.controller.on_delete_folder(item, normalized_folder_path(folder_path))

# Global exception handler functions (defined outside main block for testing)
def handle_python_exception(exc_type, exc_value, exc_traceback):
    """Handle uncaught Python exceptions"""
    if issubclass(exc_type, KeyboardInterrupt):
        # Allow Ctrl+C to work normally
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return
    
    import traceback
    from dt_image_search.telemetry.telemetry_client import log
    
    # Log the exception
    error_msg = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    log("error", "uncaught_exception", message=f"Uncaught Python exception: {error_msg}")
    print(f"FATAL ERROR: {exc_type.__name__}: {exc_value}")
    
    # Call the default handler to crash gracefully
    sys.__excepthook__(exc_type, exc_value, exc_traceback)

def handle_threading_exception(args):
    """Handle uncaught exceptions in threads"""
    import traceback
    from dt_image_search.telemetry.telemetry_client import log
    
    exc_type, exc_value, exc_traceback, thread = args
    error_msg = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    thread_name = thread.name if thread else "Unknown"
    log("error", "thread_exception", message=f"Uncaught exception in thread '{thread_name}': {error_msg}")
    print(f"THREAD ERROR in '{thread_name}': {exc_type.__name__}: {exc_value}")

def qt_message_handler(mode, context, message):
    """Handle Qt messages and log them"""
    from dt_image_search.telemetry.telemetry_client import log
    from PySide6.QtCore import QtMsgType
    
    if mode == QtMsgType.QtDebugMsg:
        log("debug", "qt", message=f"Qt Debug: {message}")
        print(f"Qt Debug: {message}")
    elif mode == QtMsgType.QtInfoMsg:
        log("info", "qt", message=f"Qt Info: {message}")
        print(f"Qt Info: {message}")
    elif mode == QtMsgType.QtWarningMsg:
        log("warning", "qt", message=f"Qt Warning: {message}")
        print(f"Qt Warning: {message}")
    elif mode == QtMsgType.QtCriticalMsg:
        log("error", "qt_critical", message=f"Qt Critical: {message}")
        print(f"Qt CRITICAL: {message}")
    elif mode == QtMsgType.QtFatalMsg:
        log("error", "qt_fatal", message=f"Qt Fatal: {message}")
        print(f"Qt FATAL: {message}")

if __name__ == '__main__':
    # Protect against multiprocessing import issues on Windows
    import multiprocessing
    multiprocessing.freeze_support()

    # Install the exception handlers
    sys.excepthook = handle_python_exception
    
    # Install threading exception handler (available in Python 3.8+)
    if hasattr(threading, 'excepthook'):
        threading.excepthook = handle_threading_exception

    startup_counter.add(1)

    index_init()  # Initialize the index system
    resume_index_workers()  # Resume workers to continue indexing after app start
    
    app = QApplication(sys.argv)
    
    # Install Qt message handler
    from PySide6.QtCore import qInstallMessageHandler
    qInstallMessageHandler(qt_message_handler)
    
    window = MainWindow()
    QCoreApplication.instance().aboutToQuit.connect(flush_telemetry)
    window.show()
    sys.exit(app.exec())
