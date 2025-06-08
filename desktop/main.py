import os
import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView
from PySide6.QtGui import QPixmap
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QSize

from ui.mainwindow_ui import Ui_MainWindow
from browse.BrowseController import BrowseController

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        self.controller = BrowseController()

        self.ui.addFolderButton.clicked.connect(self.select_folder)
        self.ui.folderList.currentRowChanged.connect(self.display_folder_images)
        self.ui.searchInput.textChanged.connect(self.handle_search)

        self.ui.imageListView.setModel(self.controller.image_list_model())
        self.ui.imageListView.setViewMode(QListView.IconMode)
        self.ui.imageListView.setResizeMode(QListView.Adjust)
        self.ui.imageListView.setUniformItemSizes(True)
        self.ui.imageListView.setIconSize(QSize(150, 150))
        self.ui.imageListView.setSpacing(10)
        self.ui.imageListView.setSelectionMode(QAbstractItemView.NoSelection)

    def select_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
        self.controller.on_folder_added(folder)
    
    def display_folder_images(self, index):
        self.controller.on_folder_selected(index)

    def handle_search(self, query):
        pass

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
