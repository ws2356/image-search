import os
import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QAbstractItemView, QWidget, QListView
from PySide6.QtGui import QPixmap
from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, QSize

from ui.mainwindow_ui import Ui_MainWindow
from ui.models.image_list_model import ImageListModel

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        self.model = ImageListModel()

        self.folder_paths = []

        self.ui.addFolderButton.clicked.connect(self.select_folder)
        self.ui.folderList.currentRowChanged.connect(self.display_folder_images)
        self.ui.searchInput.textChanged.connect(self.handle_search)
        self.folder = None

        self.ui.imageListView.setModel(self.model)
        self.ui.imageListView.setViewMode(QListView.IconMode)
        self.ui.imageListView.setResizeMode(QListView.Adjust)
        self.ui.imageListView.setUniformItemSizes(True)
        self.ui.imageListView.setIconSize(QSize(150, 150))
        self.ui.imageListView.setSpacing(10)
        self.ui.imageListView.setSelectionMode(QAbstractItemView.NoSelection)

    def select_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Image Folder")
        if folder and folder not in self.folder_paths:
            self.folder_paths.append(folder)
            self.model.load_images_from_folder(folder)

    def display_folder_images(self, index):
        if index < 0 or index >= len(self.folder_paths):
            return
        self.model.load_images_from_folder(self.folder_paths[index])

    def handle_search(self, query):
        pass

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
