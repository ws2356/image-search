import os
import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView, QMenu
from PySide6.QtGui import QPixmap
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QSize

from dt_image_search.view.mainwindow_ui import Ui_MainWindow
from dt_image_search.browse.BrowseController import BrowseController
from dt_image_search.logging import setup_logging

setup_logging()

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        self.controller = BrowseController()

        self.ui.addFolderButton.clicked.connect(self.on_add_folder_button_click)
        self.ui.folderTreeView.setModel(self.controller.folder_list_model())
        self.ui.folderTreeView.selectionModel().currentChanged.connect(self.controller.on_folder_selected)
        self.ui.folderTreeView.expanded.connect(self.controller.on_item_expanded)
        self.ui.folderTreeView.setContextMenuPolicy(Qt.CustomContextMenu)
        self.ui.folderTreeView.customContextMenuRequested.connect(self.show_tree_context_menu)

        self.ui.searchInput.textChanged.connect(self.handle_search)

        self.ui.imageListView.setModel(self.controller.image_list_model())
        self.ui.imageListView.setViewMode(QListView.IconMode)
        self.ui.imageListView.setResizeMode(QListView.Adjust)
        self.ui.imageListView.setUniformItemSizes(True)
        self.ui.imageListView.setIconSize(QSize(150, 150))
        self.ui.imageListView.setSpacing(10)
        self.ui.imageListView.setSelectionMode(QAbstractItemView.NoSelection)

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
        pass

    def show_tree_context_menu(self, pos):
        index = self.ui.folderTreeView.indexAt(pos)
        item = self.ui.folderTreeView.model().itemFromIndex(index)
        if not item or item.parent():
            return  # Only for root folders
        menu = QMenu(self)
        remove_action = menu.addAction("Remove Folder")
        if menu.exec(self.ui.folderTreeView.mapToGlobal(pos)) == remove_action:
            self.controller.on_delete_folder(index)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
