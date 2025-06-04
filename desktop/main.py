import os
import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QLabel, QWidget, QGridLayout
from PySide6.QtGui import QPixmap
from PySide6.QtCore import Qt

from ui.mainwindow_ui import Ui_MainWindow

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        # Layout for grid of images inside scroll area
        self.image_grid_layout = QGridLayout()
        self.image_container = QWidget()
        self.image_container.setLayout(self.image_grid_layout)
        self.ui.imageScrollArea.setWidget(self.image_container)

        self.folder_paths = []

        self.ui.addFolderButton.clicked.connect(self.add_folder)
        self.ui.folderList.currentRowChanged.connect(self.display_folder_images)
        self.ui.searchInput.textChanged.connect(self.handle_search)


    def add_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Folder")
        if folder and folder not in self.folder_paths:
            self.folder_paths.append(folder)
            self.load_images_from_folder(folder)
            self.ui.folderList.addItem(os.path.basename(folder))

    def display_folder_images(self, index):
        if index < 0 or index >= len(self.folder_paths):
            return
        folder = self.folder_paths[index]
        self.load_images_from_folder(folder)

    def load_images_from_folder(self, folder):
        # Clear old thumbnails
        for i in reversed(range(self.image_grid_layout.count())):
            widget = self.image_grid_layout.itemAt(i).widget()
            if widget:
                widget.setParent(None)

        image_exts = (".png", ".jpg", ".jpeg", ".bmp", ".gif")
        files = [f for f in os.listdir(folder) if f.lower().endswith(image_exts)]

        row = col = 0
        for file in files:
            path = os.path.join(folder, file)
            pixmap = QPixmap(path).scaled(150, 150, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            label = QLabel()
            label.setPixmap(pixmap)
            self.image_grid_layout.addWidget(label, row, col)
            col += 1
            if col >= 4:
                col = 0
                row += 1

    def handle_search(self, query):
        pass


if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
