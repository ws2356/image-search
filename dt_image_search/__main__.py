import os
import sys
import threading

# Add the parent directory of this file (i.e. the one that contains dt_image_search/)
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView, QMenu
from PySide6.QtCore import QCoreApplication, Qt, Slot, QSize, QUrl

QCoreApplication.setOrganizationName("net.boldman")
QCoreApplication.setApplicationName("imagesearch")

from PySide6.QtGui import QDesktopServices
import subprocess

from dt_image_search.view.dts_mainwindow_ui import Ui_MainWindow
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.search.SearchController import SearchController
from dt_image_search.index.dts_index import init as index_init
from dt_image_search.index.index_worker import resume_index_workers
from dt_image_search.telemetry.telemetry_client import flush_telemetry, startup_counter
from dt_image_search.tools.dts_util import normalized_folder_path
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.view.dts_esc_clear_event_filter import DTSEscClearEventFilter
from dt_image_search.fs.bm_fs_monitor import start_watch, stop_watch
from dt_image_search.index.incremental_index_worker import init_incremental_index_workers
from dt_image_search.bm_context import get_context, BMContext

os.environ['KMP_DUPLICATE_LIB_OK'] = 'true'

_BrowseMode = 1
_SearchMode = 2


class MainWindow(QMainWindow):
    def __init__(self, ctx: BMContext):
        super().__init__()
        self.ctx = ctx
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

        status_bar_messenger.show_status_message.connect(self._on_show_status_message)

        self.esc_clear_filter = DTSEscClearEventFilter(self)
        self.ui.searchInput.installEventFilter(self.esc_clear_filter)
        self._register_image_list_double_click_handler()
        self._register_image_list_context_menu_handler()

    @property
    def image_list_view(self):
        if self._mode == _SearchMode:
            return self.ui.searchImageListView
        elif self._mode == _BrowseMode:
            return self.ui.browseImageListView

    def _register_image_list_context_menu_handler(self):
        self.image_list_view.setContextMenuPolicy(Qt.CustomContextMenu)
        self.image_list_view.customContextMenuRequested.disconnect(self.on_image_list_context_menu)
        self.image_list_view.customContextMenuRequested.connect(self.on_image_list_context_menu)

    def _register_image_list_double_click_handler(self):
        self.image_list_view.doubleClicked.connect(self.controller.on_image_double_clicked)

    def _unregister_image_list_double_click_handler(self):
        self.image_list_view.doubleClicked.disconnect(self.controller.on_image_double_clicked)

    @Slot(str)
    def _on_show_status_message(self, message):
        self.statusBar().showMessage(message, 60000)

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
                self._unregister_image_list_double_click_handler()

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

                self._register_image_list_double_click_handler()
                self._register_image_list_context_menu_handler()
            self.controller.on_search_query(query)
        else:
            if self._mode != _BrowseMode:
                self._unregister_image_list_double_click_handler()

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
                self._register_image_list_double_click_handler()
                self._register_image_list_context_menu_handler()
        

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

    def on_image_list_context_menu(self, pos):
        index = self.image_list_view.indexAt(pos)
        if not index.isValid():
            return
        # Get image file path from model
        file_path = index.data(Qt.UserRole)
        if not file_path:
            return
        if file_path and sys.platform == "win32":
            file_path = file_path.replace('/', '\\')

        menu = QMenu(self)
        reveal_action = menu.addAction("Reveal File Location")
        copy_path_action = menu.addAction("Copy File Path")
        action = menu.exec(self.image_list_view.viewport().mapToGlobal(pos))
        if action == reveal_action:
            folder = os.path.dirname(file_path)
            # Open folder and select file (platform-specific)
            if sys.platform == "win32":
                subprocess.run(['explorer', '/select,', file_path])
            elif sys.platform == "darwin":
                subprocess.run(['open', '-R', file_path])
            else:  # Linux
                QDesktopServices.openUrl(QUrl.fromLocalFile(folder))
        elif action == copy_path_action:
            clipboard = QApplication.instance().clipboard()
            clipboard.setText(file_path)

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

    app = QApplication(sys.argv)

    startup_counter.add(1)
    ctx = get_context()

    index_init(ctx)  # Initialize the index system
    init_incremental_index_workers(ctx)  # Initialize incremental index workers
    resume_index_workers(ctx)  # Resume workers to continue indexing after app start
    start_watch(ctx)  # Start watching file system changes
    
    # Install Qt message handler
    from PySide6.QtCore import qInstallMessageHandler
    qInstallMessageHandler(qt_message_handler)

    window = MainWindow(ctx=ctx)
    QCoreApplication.instance().aboutToQuit.connect(flush_telemetry)
    window.show()
    sys.exit(app.exec())
