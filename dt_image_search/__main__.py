import argparse
import os
import plistlib
import time
os.environ['KMP_DUPLICATE_LIB_OK'] = 'TRUE'
os.environ['OMP_NUM_THREADS'] = '1'
os.environ['MKL_NUM_THREADS'] = '1'

import sys
import threading
from importlib.resources import as_file, files

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

from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView, QMenu, QLineEdit, QStyle, QSystemTrayIcon, QMessageBox, QLabel
from PySide6.QtCore import QCoreApplication, QTimer, Qt, Slot, Signal, QSize, QUrl, QItemSelectionModel, QPersistentModelIndex, QModelIndex, QLockFile
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from dt_image_search.build_flavor import get_build_type

QCoreApplication.setOrganizationName("net.boldman")
_build_type = get_build_type()
_app_display_name = "imagesearch-dev" if _build_type == "dev" else "imagesearch"
QCoreApplication.setApplicationName(_app_display_name)

from dt_image_search.bm_context import get_context, BMContext
from dt_image_search.model.dts_config import setup_model_cache
from dt_image_search.model.feature_flags import (
    DesktopVersionFlag,
    get_version_update_requirement,
    initialize_feature_flags,
    is_mobile_folder_enabled,
)
from dt_image_search.model.dts_fs import get_app_data_path
ctx = get_context()
setup_model_cache(ctx=ctx)

from PySide6.QtGui import QAction, QDesktopServices, QIcon, QStandardItem
import subprocess

from dt_image_search.view.dts_mainwindow_ui import Ui_MainWindow
from dt_image_search.view.dts_update_prompt_dialog import UpdatePromptDialog
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.search.SearchController import SearchController
from dt_image_search.index.index_worker import init_index_workers, deinit_index_workers
from dt_image_search.telemetry.telemetry_client import flush_telemetry, startup_counter
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.tools.dts_util import normalized_folder_path
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.view.dts_esc_clear_event_filter import DTSEscClearEventFilter
from dt_image_search.view.folder_tree_item_delegate import FolderTreeItemDelegate
from dt_image_search.fs.bm_fs_monitor import start_watch, stop_watch, remove_folder
from dt_image_search.index.incremental_index_worker import init_incremental_index_workers, deinit_incremental_index_workers
from dt_image_search.index.dts_index import init as index_init
from dt_image_search.index.dts_model_downloader import init as model_downloader_init
from dt_image_search.mobile import MobileFolderCoordinator, MobileSourceType
from dt_image_search.mobile.mobile_pairing_service import MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT
from dt_image_search.mobile.mobile_transfer_service import MOBILE_TRANSFER_DISK_FULL_EVENT
from dt_image_search.mobile.mobile_update_prompt_service import MOBILE_UPDATE_PROMPT_REQUESTED_EVENT
from dt_image_search.telemetry.crash_support import CrashRecoveryManager
from dt_image_search.tools.dts_event_bus import default_bus



_BrowseMode = 1
_SearchMode = 2
_app_lock = None
_activation_server = None
def _crash_support_log(severity: str, error_type: str = "", message: str = "", where: str = "") -> None:
    from dt_image_search.telemetry.telemetry_client import log

    log(severity, error_type=error_type, message=message, where=where)


_crash_recovery = CrashRecoveryManager(get_app_data_path(ctx), _crash_support_log)


def _load_application_icon() -> QIcon:
    icon_resource = files("dt_image_search").joinpath("resources", "icon.png")
    if not icon_resource.is_file():
        return QIcon()
    with as_file(icon_resource) as icon_path:
        return QIcon(str(icon_path))


def _load_application_version() -> str:
    plist_resource = files("dt_image_search").joinpath("resources", "AppInfo.plist")
    if not plist_resource.is_file():
        return ""
    try:
        plist_data = plistlib.loads(plist_resource.read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return ""
    short_version = plist_data.get("CFBundleShortVersionString")
    if isinstance(short_version, str):
        return short_version.strip()
    return ""


def _build_startup_update_prompt_body(version_flag: DesktopVersionFlag) -> str:
    if version_flag.required:
        return (
            f"AuSearch {version_flag.min_version} or later is required to continue. "
            "Update now to keep using the app."
        )
    return (
        f"AuSearch {version_flag.min_version} or later is available. "
        "Update now to use the latest features."
    )


def maybe_show_startup_update_prompt(window: "MainWindow", *, current_version: str | None = None) -> None:
    from dt_image_search.telemetry.telemetry_client import log

    resolved_current_version = (
        current_version
        if isinstance(current_version, str)
        else QCoreApplication.applicationVersion()
    )
    normalized_current_version = resolved_current_version.strip() if isinstance(resolved_current_version, str) else ""
    if not normalized_current_version:
        return
    version_flag = get_version_update_requirement(normalized_current_version)
    if version_flag is None:
        return
    log(
        "info",
        message=(
            "MainWindow/startup_update_prompt: showing launch update prompt "
            f"current_version={normalized_current_version} "
            f"minimum_version={version_flag.min_version} required={version_flag.required}"
        ),
    )
    window.show_update_prompt_signal.emit(
        version_flag.required,
        _build_startup_update_prompt_body(version_flag),
        "",
    )


def _activation_server_name(ctx: BMContext) -> str:
    suffix = ctx.subfolder or "default"
    return f"net.boldman.imagesearch.{_build_type}.{suffix}"


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
    show_update_prompt_signal = Signal(bool, str, str)
    show_mobile_transfer_disk_full_signal = Signal(str)

    def __init__(self, ctx: BMContext):
        super().__init__()
        from dt_image_search.telemetry.telemetry_client import log
        log("debug", message="MainWindow/__init__: initializing window")
        self.ctx = ctx
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)
        self._configure_app_menu()

        self._alternativeController = None
        self._mode = _BrowseMode
        self._update_prompt_subscription = default_bus.subscribe(
            MOBILE_UPDATE_PROMPT_REQUESTED_EVENT,
            self._on_update_prompt_requested,
        )
        self.show_update_prompt_signal.connect(self._show_update_prompt_dialog)
        self._mobile_transfer_disk_full_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_DISK_FULL_EVENT,
            self._on_mobile_transfer_disk_full_requested,
        )
        self.show_mobile_transfer_disk_full_signal.connect(
            self._show_mobile_transfer_disk_full_notification
        )
        self._notification_tray_icon: QSystemTrayIcon | None = None
        if sys.platform != "darwin" and QSystemTrayIcon.isSystemTrayAvailable():
            tray_icon = QApplication.windowIcon()
            if tray_icon.isNull():
                tray_icon = self.windowIcon()
            if tray_icon.isNull():
                tray_icon = _load_application_icon()
            if not tray_icon.isNull():
                self._notification_tray_icon = QSystemTrayIcon(self)
                self._notification_tray_icon.setIcon(tray_icon)
                self._notification_tray_icon.setToolTip("AuSearch")
                self._notification_tray_icon.show()

        self.browse_controller = BrowseController(ctx=self.ctx)
        self.controller = self.browse_controller
        self.mobile_folder_coordinator: MobileFolderCoordinator | None = None
        self.controller.is_active = True  # Set the controller to active state

        self.ui.browsePageAddFolderButton.clicked.connect(self.on_add_folder_button_click)
        self.ui.browsePageFolderTreeView.setHeaderHidden(True)
        folder_tree_model = self.browse_controller.folder_list_model()
        self.ui.browsePageFolderTreeView.setModel(folder_tree_model)
        self.ui.browsePageFolderTreeView.setItemDelegate(FolderTreeItemDelegate(self.ui.browsePageFolderTreeView))
        self.ui.browsePageFolderTreeView.setRootIsDecorated(False)
        self.ui.browsePageFolderTreeView.setIndentation(8)
        self.ui.browsePageFolderTreeView.setExpandsOnDoubleClick(False)
        self.ui.browsePageFolderTreeView.clicked.connect(self._on_folder_tree_item_clicked)
        self.ui.browsePageFolderTreeView.collapsed.connect(self._on_folder_tree_item_collapsed)
        folder_tree_model.rowsInserted.connect(lambda *_: self._expand_section_headers())
        folder_tree_model.modelReset.connect(self._expand_section_headers)
        self._expand_section_headers()
        QTimer.singleShot(0, self._expand_section_headers)
        existing_tree_style = self.ui.browsePageFolderTreeView.styleSheet()
        tree_style = (
            "QTreeView { show-decoration-selected: 1; background-color: #FFFFFF; }\n"
            "QTreeView::item { background-color: #FFFFFF; color: #333333; }\n"
            "QTreeView::item:selected,\n"
            "QTreeView::item:selected:active,\n"
            "QTreeView::item:selected:!active { background-color: #E8F0FD; color: #1A1A1A; }\n"
            "QTreeView::branch { width: 0px; background: transparent; border: none; image: none; }\n"
            "QTreeView::branch:selected,\n"
            "QTreeView::branch:selected:active,\n"
            "QTreeView::branch:selected:!active { background: #E8F0FD; }\n"
            "QTreeView::branch:has-children,\n"
            "QTreeView::branch:open,\n"
            "QTreeView::branch:closed,\n"
            "QTreeView::branch:has-siblings,\n"
            "QTreeView::branch:adjoins-item { image: none; }"
        )
        if tree_style not in existing_tree_style:
            merged_style = f"{existing_tree_style}\n{tree_style}" if existing_tree_style else tree_style
            self.ui.browsePageFolderTreeView.setStyleSheet(merged_style)
        self.ui.browsePageFolderTreeView.selectionModel().currentChanged.connect(self.controller.on_folder_selected)
        self.ui.browsePageFolderTreeView.expanded.connect(self.controller.on_item_expanded)
        self.ui.browsePageFolderTreeView.setContextMenuPolicy(Qt.CustomContextMenu)
        self.ui.browsePageFolderTreeView.customContextMenuRequested.connect(self.show_tree_context_menu)
        
        # Connect folder selection signal to auto-select folders in the tree view
        self.browse_controller.folder_selection_signal.select_folder.connect(self.select_folder_in_tree)

        self.image_list_view.setModel(self.controller.image_list_model())

        self._configure_search_field_ui()
        self.ui.searchInputField.textChanged.connect(self.handle_search)
        self.ui.searchInputField.setClearButtonEnabled(True)

        for view in [self.ui.searchPageImageListView, self.ui.browsePageImageListView]:
            view.setEditTriggers(QAbstractItemView.NoEditTriggers)
            view.setDragEnabled(False)
            view.setAcceptDrops(False)
            view.setDropIndicatorShown(False)
            view.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

            view.setViewMode(QListView.IconMode)
            view.setLayoutMode(QListView.Batched)
            view.setBatchSize(100)
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

    def _on_update_prompt_requested(
        self,
        *,
        required: object,
        body_text: object = None,
        update_destination: object = None,
        **_: object,
    ) -> None:
        required_value = bool(required)
        body_text_value = body_text if isinstance(body_text, str) else ""
        update_destination_value = update_destination if isinstance(update_destination, str) else ""
        self.show_update_prompt_signal.emit(
            required_value,
            body_text_value,
            update_destination_value,
        )

    @Slot(bool, str, str)
    def _show_update_prompt_dialog(
        self,
        required: bool,
        body_text: str,
        update_destination: str,
    ) -> None:
        dialog = UpdatePromptDialog(
            is_required=required,
            body_text=body_text or None,
            update_destination=update_destination or None,
            parent=self,
        )
        dialog.exec()

    def _on_mobile_transfer_disk_full_requested(
        self,
        *,
        message: object = None,
        **_: object,
    ) -> None:
        notification_message = (
            message
            if isinstance(message, str) and message.strip()
            else "Desktop storage is full. Free up disk space and retry mobile backup."
        )
        self.show_mobile_transfer_disk_full_signal.emit(notification_message)

    @Slot(str)
    def _show_mobile_transfer_disk_full_notification(self, message: str) -> None:
        self.statusBar().showMessage(message)
        if self._notification_tray_icon is not None and self._notification_tray_icon.supportsMessages():
            self._notification_tray_icon.showMessage(
                "Mobile Backup Failed",
                message,
                QSystemTrayIcon.MessageIcon.Warning,
                15000,
            )

    def _configure_app_menu(self) -> None:
        if sys.platform != "darwin":
            return

        menu_bar = self.menuBar()
        if menu_bar is None:
            return
        menu_bar.clear()
        app_menu = menu_bar.addMenu("AuSearch")

        about_action = QAction("About AuSearch", self)
        about_action.setMenuRole(QAction.MenuRole.AboutRole)
        about_action.triggered.connect(self._show_about_dialog)
        app_menu.addAction(about_action)

        app_menu.addSeparator()

        quit_action = QAction("Quit AuSearch", self)
        quit_action.setMenuRole(QAction.MenuRole.QuitRole)
        quit_action.setShortcut("Meta+Q")
        quit_action.triggered.connect(QApplication.instance().quit)
        app_menu.addAction(quit_action)

    def _show_about_dialog(self) -> None:
        version_text = QCoreApplication.applicationVersion() or "Unknown"
        message_box = QMessageBox(self)
        message_box.setWindowTitle("About AuSearch")
        message_box.setTextFormat(Qt.TextFormat.RichText)
        message_box.setText(
            "<b>AuSearch</b><br/>"
            f"Version {version_text}<br/><br/>"
            "Download the latest version:<br/>"
            '<a href="https://aurora.boldman.net">https://aurora.boldman.net</a>'
        )
        message_box.setStandardButtons(QMessageBox.StandardButton.Ok)
        message_box.setTextInteractionFlags(Qt.TextInteractionFlag.TextBrowserInteraction)
        for label in message_box.findChildren(QLabel):
            label.setOpenExternalLinks(True)
        message_box.exec()

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

    def _configure_search_field_ui(self):
        search_icon = QIcon.fromTheme("edit-find")
        if search_icon.isNull():
            search_icon = self.style().standardIcon(QStyle.SP_FileDialogContentsView)
        self._search_field_icon_action = QAction(self.ui.searchInputField)
        self._search_field_icon_action.setIcon(search_icon)
        self.ui.searchInputField.addAction(self._search_field_icon_action, QLineEdit.LeadingPosition)
        self.ui.searchInputField.setTextMargins(0, 0, 0, 0)

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
            if is_mobile_folder_enabled():
                selected_source = self._ensure_mobile_folder_coordinator().choose_source(self)
                if selected_source is None:
                    return

                if selected_source == MobileSourceType.MOBILE_DEVICE:
                    self._ensure_mobile_folder_coordinator().start_pairing_flow(self)
                    return

                folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
            else:
                folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
            
        if not folder:
            return

        self.controller.on_folder_added(normalized_folder_path(folder))

    def _ensure_mobile_folder_coordinator(self) -> MobileFolderCoordinator:
        if self.mobile_folder_coordinator is None:
            self.mobile_folder_coordinator = MobileFolderCoordinator(
                ctx=self.ctx,
                on_folder_ready=self._on_mobile_transfer_folder_ready,
            )
        return self.mobile_folder_coordinator
    
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
                self.controller = tmp_controller or self.browse_controller
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
        model = self.ui.browsePageFolderTreeView.model()
        item = model.itemFromIndex(index) if model else None
        is_root_folder = bool(item and hasattr(model, "is_top_level_folder_item") and model.is_top_level_folder_item(item))
        if not is_root_folder:
            return
        folder_path = item.data(Qt.UserRole) if item else None
        if not folder_path:
            return
        is_mobile_folder = bool(
            model
            and hasattr(model, "is_mobile_folder_path")
            and model.is_mobile_folder_path(folder_path)
        )
        menu = QMenu(self)
        if is_mobile_folder and is_mobile_folder_enabled():
            backup_again_action = menu.addAction("Back Up Again")
            backup_again_action.triggered.connect(
                lambda: self._start_mobile_folder_backup_again(folder_path)
            )
            menu.addSeparator()
        open_action = menu.addAction("Open Folder")
        open_action.triggered.connect(lambda: self._open_folder_in_explorer(folder_path))
        menu.addSeparator()
        remove_action = menu.addAction("Remove Folder")
        remove_action.triggered.connect(lambda: QTimer.singleShot(200, lambda: self.safe_execute_delete(p_index, folder_path)))
        menu.exec(self.ui.browsePageFolderTreeView.mapToGlobal(pos))

    def _start_mobile_folder_backup_again(self, folder_path: str) -> None:
        self._ensure_mobile_folder_coordinator().start_backup_again_flow(folder_path, self)

    def safe_execute_delete(self, p_index, folder_path):
        if not p_index.isValid():
            return
        if self.ui.browsePageFolderTreeView.isExpanded(p_index):
            self.ui.browsePageFolderTreeView.collapse(p_index)
        self.controller.on_delete_folder(p_index, normalized_folder_path(folder_path))

    def _open_folder_in_explorer(self, folder_path: str) -> None:
        target_path = normalized_folder_path(folder_path)
        if not os.path.isdir(target_path):
            from dt_image_search.telemetry.telemetry_client import log
            log("warning", message=f"MainWindow/_open_folder_in_explorer: path does not exist: {target_path}")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(target_path))

    def select_folder_in_tree(self, folder_item: QStandardItem):
        """Select and expand to show the specified folder in the tree view."""
        model = self.ui.browsePageFolderTreeView.model()
        
        # Get the model index for the item
        folder_index = model.indexFromItem(folder_item)
        if not folder_index.isValid():
            return
        
        parent_indexes = []
        parent_index = folder_index.parent()
        while parent_index.isValid():
            parent_indexes.append(parent_index)
            parent_index = parent_index.parent()
        for parent_index in reversed(parent_indexes):
            if hasattr(model, "expand_subfolders"):
                model.expand_subfolders(parent_index)
            elif model.canFetchMore(parent_index):
                model.fetchMore(parent_index)
            self.ui.browsePageFolderTreeView.expand(parent_index)
        if hasattr(model, "expand_subfolders"):
            model.expand_subfolders(folder_index)
        elif model.canFetchMore(folder_index):
            model.fetchMore(folder_index)
        self.ui.browsePageFolderTreeView.expand(folder_index)
        
        # Select the folder
        selection_model = self.ui.browsePageFolderTreeView.selectionModel()
        selection_model.setCurrentIndex(folder_index, QItemSelectionModel.SelectionFlag.ClearAndSelect)
        
        # Scroll to make the selected item visible
        self.ui.browsePageFolderTreeView.scrollTo(folder_index)
        
        from dt_image_search.telemetry.telemetry_client import log
        log("debug", message=f"Auto-selected folder in tree: {folder_item.data(Qt.UserRole)}")

    def _expand_section_headers(self):
        model = self.ui.browsePageFolderTreeView.model()
        if model is None:
            return
        for row in range(model.rowCount()):
            index = model.index(row, 0)
            if not index.isValid():
                continue
            item = model.itemFromIndex(index)
            if item is not None and item.data(FolderTreeModel.SECTION_ROLE):
                self.ui.browsePageFolderTreeView.expand(index)

    def _on_folder_tree_item_collapsed(self, index):
        model = self.ui.browsePageFolderTreeView.model()
        if model is None:
            return
        item = model.itemFromIndex(index)
        if item is None or not item.data(FolderTreeModel.SECTION_ROLE):
            return
        persistent_index = QPersistentModelIndex(index)
        QTimer.singleShot(0, lambda: self._expand_section_if_valid(persistent_index))

    def _expand_section_if_valid(self, index: QPersistentModelIndex):
        if not index.isValid():
            return
        self.ui.browsePageFolderTreeView.expand(index)

    def _on_folder_tree_item_clicked(self, index: QModelIndex):
        if not index.isValid():
            return
        model = self.ui.browsePageFolderTreeView.model()
        if model is None:
            return
        item = model.itemFromIndex(index)
        if item is None or item.data(FolderTreeModel.SECTION_ROLE):
            return
        if model.rowCount(index) <= 0 and not model.canFetchMore(index):
            return
        if self.ui.browsePageFolderTreeView.isExpanded(index):
            self.ui.browsePageFolderTreeView.collapse(index)
            return
        if hasattr(model, "expand_subfolders"):
            model.expand_subfolders(index)
        elif model.canFetchMore(index):
            model.fetchMore(index)
        self.ui.browsePageFolderTreeView.expand(index)

    def _on_mobile_transfer_folder_ready(self, folder_path: str):
        self.browse_controller.ensure_folder_registered(normalized_folder_path(folder_path))

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

    def closeEvent(self, event):
        if self._update_prompt_subscription is not None:
            self._update_prompt_subscription.dispose()
            self._update_prompt_subscription = None
        if self._mobile_transfer_disk_full_subscription is not None:
            self._mobile_transfer_disk_full_subscription.dispose()
            self._mobile_transfer_disk_full_subscription = None
        if self._notification_tray_icon is not None:
            self._notification_tray_icon.hide()
            self._notification_tray_icon = None
        super().closeEvent(event)

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
    _crash_recovery.disable_native_crash_dump_capture()
    stop_watch()
    flush_telemetry()
    _crash_recovery.clear_run_marker()
    deinit_incremental_index_workers()
    deinit_index_workers()
    close_activation_server()
    release_single_instance_lock()


def _publish_app_foreground_state(
    app: QApplication,
    app_state: Qt.ApplicationState | None = None,
) -> None:
    current_state = app_state if app_state is not None else app.applicationState()
    is_foreground = current_state == Qt.ApplicationState.ApplicationActive
    default_bus.publish(
        MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT,
        is_foreground=is_foreground,
    )

def main():
    # Protect against multiprocessing import issues on Windows
    import multiprocessing
    multiprocessing.freeze_support()

    # Install the exception handlers
    sys.excepthook = handle_python_exception
    
    # Install threading exception handler (available in Python 3.8+)
    if hasattr(threading, 'excepthook'):
        threading.excepthook = handle_threading_exception

    initialize_feature_flags()

    app = QApplication(sys.argv)
    app_icon = _load_application_icon()
    if not app_icon.isNull():
        app.setWindowIcon(app_icon)
    app_version = _load_application_version()
    if app_version:
        app.setApplicationVersion(app_version)
    _publish_app_foreground_state(app)
    app.applicationStateChanged.connect(
        lambda state: _publish_app_foreground_state(app, state)
    )

    if not acquire_single_instance_lock(ctx):
        send_activation_request(ctx)
        sys.exit(0)

    _crash_recovery.ingest_previous_native_crash_dump()
    _crash_recovery.enable_native_crash_dump_capture()
    _crash_recovery.mark_run_started()

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
    QTimer.singleShot(0, lambda: maybe_show_startup_update_prompt(window))
    sys.exit(app.exec())

if __name__ == '__main__':
    main()
