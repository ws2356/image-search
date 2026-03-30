import argparse
import os
import time
from pathlib import Path
os.environ['KMP_DUPLICATE_LIB_OK'] = 'TRUE'
os.environ['OMP_NUM_THREADS'] = '1'
os.environ['MKL_NUM_THREADS'] = '1'

import sys
import threading

import sys
import threading

# TODO: may not need this
args = argparse.ArgumentParser()
args.add_argument("--test-folder", type=str, help="Path to the test folder containing images for UI testing")
args.add_argument("--ui-test", type=int, help="Flag to indicate running in UI test mode")
args.add_argument("--hf-hub-offline", type=int, help="Run in offline mode using cached models from Hugging Face Hub")
parsed_args, unknown = args.parse_known_args()
if parsed_args.ui_test:
    os.environ['UI_TEST'] = '1'
if parsed_args.test_folder:
    os.environ['TEST_FOLDER'] = parsed_args.test_folder
if parsed_args.hf_hub_offline:
    os.environ['HF_HUB_OFFLINE'] = '1'

# Add the parent directory of this file (i.e. the one that contains dt_image_search/)
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView, QMenu
from PySide6.QtCore import QCoreApplication, QTimer, Qt, Slot, QSize, QUrl, QItemSelectionModel, QPersistentModelIndex, QLockFile
from PySide6.QtNetwork import QLocalServer, QLocalSocket

QCoreApplication.setOrganizationName("net.boldman")
QCoreApplication.setApplicationName("imagesearch")

from dt_image_search.bm_context import get_context, BMContext
from dt_image_search.model.dts_config import setup_model_cache
from dt_image_search.model.dts_fs import get_app_data_path
ctx = get_context()
setup_model_cache(ctx=ctx)

from PySide6.QtGui import QDesktopServices, QStandardItem
import subprocess

from dt_image_search.view.dts_mainwindow_ui import Ui_MainWindow
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.search.SearchController import SearchController
from dt_image_search.index.index_worker import init_index_workers, deinit_index_workers
from dt_image_search.telemetry.telemetry_client import flush_telemetry, startup_counter
from dt_image_search.tools.dts_util import normalized_folder_path
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.view.dts_esc_clear_event_filter import DTSEscClearEventFilter
from dt_image_search.fs.bm_fs_monitor import start_watch, stop_watch, remove_folder
from dt_image_search.index.incremental_index_worker import init_incremental_index_workers, deinit_incremental_index_workers
from dt_image_search.index.dts_index import init as index_init
from dt_image_search.index.dts_model_downloader import init as model_downloader_init



_BrowseMode = 1
_SearchMode = 2
_app_lock = None
_activation_server = None
_CRASH_MARKER_FILENAME = "run.marker"


def _get_crash_marker_path(ctx: BMContext) -> Path:
    return get_app_data_path(ctx) / _CRASH_MARKER_FILENAME


def mark_run_started(ctx: BMContext) -> None:
    from dt_image_search.telemetry.telemetry_client import log

    marker_path = _get_crash_marker_path(ctx)

    if marker_path.exists():
        try:
            stale_timestamp = marker_path.read_text(encoding="utf-8").strip()
        except Exception:
            stale_timestamp = "unknown"
        log(
            "warning",
            "previous_run_unclean",
            message=f"Detected stale run marker. Previous run may have crashed. marker_time={stale_timestamp}",
            where="mark_run_started",
        )

    marker_path.write_text(str(int(time.time())), encoding="utf-8")


def clear_run_marker(ctx: BMContext) -> None:
    from dt_image_search.telemetry.telemetry_client import log

    marker_path = _get_crash_marker_path(ctx)
    try:
        if marker_path.exists():
            marker_path.unlink()
    except Exception as e:
        log("warning", "run_marker_cleanup_failed", message=str(e), where="clear_run_marker")


def _activation_server_name(ctx: BMContext) -> str:
    suffix = ctx.subfolder or "default"
    return f"net.boldman.imagesearch.{suffix}"


def acquire_single_instance_lock(ctx: BMContext) -> bool:
    global _app_lock

    lock_path = str(get_app_data_path(ctx) / "app_instance.lock")
    _app_lock = QLockFile(lock_path)
    # Keep stale detection tied to process lifetime for this long-running GUI app.
    _app_lock.setStaleLockTime(0)
    return _app_lock.tryLock(0)


def release_single_instance_lock() -> None:
    global _app_lock

    if _app_lock is None:
        return

    _app_lock.unlock()
    _app_lock = None


def send_activation_request(ctx: BMContext) -> bool:
    socket = QLocalSocket()
    socket.connectToServer(_activation_server_name(ctx))
    if not socket.waitForConnected(1000):
        return False
    socket.write(b"activate")
    socket.flush()
    socket.waitForBytesWritten(1000)
    socket.disconnectFromServer()
    return True


def close_activation_server() -> None:
    global _activation_server

    if _activation_server is None:
        return

    server_name = _activation_server.serverName()
    _activation_server.close()
    QLocalServer.removeServer(server_name)
    _activation_server = None


def setup_activation_server(ctx: BMContext, window: QMainWindow) -> None:
    global _activation_server

    server_name = _activation_server_name(ctx)
    QLocalServer.removeServer(server_name)

    _activation_server = QLocalServer()

    def handle_activation_request() -> None:
        while _activation_server.hasPendingConnections():
            connection = _activation_server.nextPendingConnection()
            if connection is None:
                continue
            connection.waitForReadyRead(250)
            connection.readAll()
            connection.disconnectFromServer()
            if window.isMinimized():
                window.showNormal()
            if not window.isVisible():
                window.show()
            window.raise_()
            window.activateWindow()
            if hasattr(window, "ui") and getattr(window.ui, "searchInputField", None) is not None:
                QTimer.singleShot(0, lambda: window.ui.searchInputField.setFocus(Qt.ActiveWindowFocusReason))

    _activation_server.newConnection.connect(handle_activation_request)
    if not _activation_server.listen(server_name):
        QLocalServer.removeServer(server_name)
        _activation_server.listen(server_name)


class MainWindow(QMainWindow):
    def __init__(self, ctx: BMContext):
        super().__init__()
        from dt_image_search.telemetry.telemetry_client import log
        log("debug", message="MainWindow/__init__: initializing window")
        self.ctx = ctx
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        self._alternativeController = None
        self._mode = _BrowseMode

        self.controller = BrowseController(ctx=self.ctx)
        self.controller.is_active = True  # Set the controller to active state

        self.ui.browsePageAddFolderButton.clicked.connect(self.on_add_folder_button_click)
        self.ui.browsePageFolderTreeView.setModel(self.controller.folder_list_model())
        self.ui.browsePageFolderTreeView.selectionModel().currentChanged.connect(self.controller.on_folder_selected)
        self.ui.browsePageFolderTreeView.expanded.connect(self.controller.on_item_expanded)
        self.ui.browsePageFolderTreeView.setContextMenuPolicy(Qt.CustomContextMenu)
        self.ui.browsePageFolderTreeView.customContextMenuRequested.connect(self.show_tree_context_menu)
        
        # Connect folder selection signal to auto-select folders in the tree view
        self.controller.folder_selection_signal.select_folder.connect(self.select_folder_in_tree)

        self.image_list_view.setModel(self.controller.image_list_model())

        self.ui.searchInputField.textChanged.connect(self.handle_search)
        self.ui.searchInputField.setClearButtonEnabled(True)

        for view in [self.ui.searchPageImageListView, self.ui.browsePageImageListView]:
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
        self.ui.searchInputField.installEventFilter(self.esc_clear_filter)
        self._register_image_list_double_click_handler()
        self._register_image_list_context_menu_handler()

    @property
    def image_list_view(self):
        if self._mode == _SearchMode:
            return self.ui.searchPageImageListView
        elif self._mode == _BrowseMode:
            return self.ui.browsePageImageListView

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
        self.statusBar().showMessage(message)
        if sys.platform == "darwin":
            self.statusBar().setAccessibleName(message)  # Update accessible name for screen readers

    def on_add_folder_button_click(self):
        if os.environ.get('UI_TEST') == '1' and 'TEST_FOLDER' in os.environ:
            folder = os.environ['TEST_FOLDER']
            # This logic path often hit app crash, so adding a small delay to help mitigate
            # Small delay to simulate user interaction and allow UI to update
            time.sleep(5)
        else:
            folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
            
        if not folder:
            return

        self.controller.on_folder_added(normalized_folder_path(folder))
    
    def handle_search(self, query):
        query = query.strip()
        tmp_controller = self._alternativeController
        if query:
            if self._mode != _SearchMode:
                self._unregister_image_list_double_click_handler()

                self._mode = _SearchMode

                self._alternativeController = self.controller
                self.controller = tmp_controller or SearchController(ctx=self.ctx)
                self._alternativeController.is_active = False  # Deactivate the alternative controller
                self.controller.is_active = True
                self.image_list_view.setModel(self.controller.image_list_model())
                self.ui.mainStack.setCurrentWidget(self.ui.searchPage)
                # Update layout
                self.ui.browsePage.layout().removeWidget(self.ui.searchInputField)
                self.ui.searchPage.layout().insertWidget(0, self.ui.searchInputField)
                self.ui.searchInputField.setFocus()

                self._register_image_list_double_click_handler()
                self._register_image_list_context_menu_handler()
            self.controller.on_search_query(query)
        else:
            if self._mode != _BrowseMode:
                self._unregister_image_list_double_click_handler()

                self._mode = _BrowseMode
                self._alternativeController = self.controller
                self.controller = tmp_controller or BrowseController(ctx=self.ctx)
                self._alternativeController.is_active = False  # Deactivate the alternative controller
                self.controller.is_active = True
                self.image_list_view.setModel(self.controller.image_list_model())
                self.ui.mainStack.setCurrentWidget(self.ui.browsePage)
                # Update layout
                self.ui.searchPage.layout().removeWidget(self.ui.searchInputField)
                self.ui.browseLeftPanel.layout().insertWidget(0, self.ui.searchInputField)
                self.ui.searchInputField.setFocus()
                self._register_image_list_double_click_handler()
                self._register_image_list_context_menu_handler()
        

    def show_tree_context_menu(self, pos):
        index = self.ui.browsePageFolderTreeView.indexAt(pos)
        p_index = QPersistentModelIndex(index)
        item = self.ui.browsePageFolderTreeView.model().itemFromIndex(index)
        is_root_folder = item and not item.parent()
        if not is_root_folder:
            return
        folder_path = item.data(Qt.UserRole) if item else None
        if not folder_path:
            return
        menu = QMenu(self)
        remove_action = menu.addAction("Remove Folder")
        remove_action.triggered.connect(lambda: QTimer.singleShot(200, lambda: self.safe_execute_delete(p_index, folder_path)))
        menu.exec(self.ui.browsePageFolderTreeView.mapToGlobal(pos))

    def safe_execute_delete(self, p_index, folder_path):
        if not p_index.isValid():
            return
        if self.ui.browsePageFolderTreeView.isExpanded(p_index):
            self.ui.browsePageFolderTreeView.collapse(p_index)
        self.controller.on_delete_folder(p_index, normalized_folder_path(folder_path))

    def select_folder_in_tree(self, folder_item: QStandardItem):
        """Select and expand to show the specified folder in the tree view."""
        model = self.controller.folder_list_model()
        
        # Get the model index for the item
        folder_index = model.indexFromItem(folder_item)
        if not folder_index.isValid():
            return
        
        self.ui.browsePageFolderTreeView.expand(folder_index)
        
        # Select the folder
        selection_model = self.ui.browsePageFolderTreeView.selectionModel()
        selection_model.setCurrentIndex(folder_index, QItemSelectionModel.SelectionFlag.ClearAndSelect)
        
        # Scroll to make the selected item visible
        self.ui.browsePageFolderTreeView.scrollTo(folder_index)
        
        from dt_image_search.telemetry.telemetry_client import log
        log("debug", message=f"Auto-selected folder in tree: {folder_item.data(Qt.UserRole)}")

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
    from dt_image_search.telemetry.telemetry_client import log, flush_telemetry_for_fatal
    
    # Log the exception
    error_msg = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    log("error", "uncaught_exception", message=f"Uncaught Python exception: {error_msg}")
    flush_telemetry_for_fatal()
    print(f"FATAL ERROR: {exc_type.__name__}: {exc_value}")
    
    # Call the default handler to crash gracefully
    sys.__excepthook__(exc_type, exc_value, exc_traceback)

def handle_threading_exception(args):
    """Handle uncaught exceptions in threads"""
    import traceback
    from dt_image_search.telemetry.telemetry_client import log, flush_telemetry_for_fatal
    
    exc_type, exc_value, exc_traceback, thread = args
    error_msg = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    thread_name = thread.name if thread else "Unknown"
    log("error", "thread_exception", message=f"Uncaught exception in thread '{thread_name}': {error_msg}")
    flush_telemetry_for_fatal()
    print(f"THREAD ERROR in '{thread_name}': {exc_type.__name__}: {exc_value}")

def qt_message_handler(mode, context, message):
    """Handle Qt messages and log them"""
    from dt_image_search.telemetry.telemetry_client import log, flush_telemetry_for_fatal
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
        flush_telemetry_for_fatal()
        print(f"Qt FATAL: {message}")

def cleanup():
    stop_watch()
    flush_telemetry()
    clear_run_marker(ctx)
    deinit_incremental_index_workers()
    deinit_index_workers()
    close_activation_server()
    release_single_instance_lock()

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

    if not acquire_single_instance_lock(ctx):
        send_activation_request(ctx)
        sys.exit(0)

    mark_run_started(ctx)

    app.aboutToQuit.connect(cleanup)

    window = MainWindow(ctx=ctx)
    setup_activation_server(ctx, window)
    QCoreApplication.instance().aboutToQuit.connect(flush_telemetry)

    startup_counter.add(1)

    model_downloader_init(ctx)  # Start model downloader if needed
    index_init(ctx)  # Initialize the index system
    init_incremental_index_workers(ctx)  # Initialize incremental index workers
    init_index_workers(ctx)  # Initialize index workers
    start_watch(ctx)  # Start watching file system changes
    
    # Install Qt message handler
    from PySide6.QtCore import qInstallMessageHandler
    qInstallMessageHandler(qt_message_handler)

    window.show()
    sys.exit(app.exec())
