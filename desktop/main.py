import os
import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QLabel, QWidget, QGridLayout
from PySide6.QtGui import QPixmap
from PySide6.QtCore import Qt

from mainwindow_ui import Ui_MainWindow

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self._ui = Ui_MainWindow()
        self._ui.setupUi(self)
        # Connect button click to folder selection
        self._ui.selectButton.clicked.connect(self.select_folder)

                # Layout for grid of images inside scroll area
        self.grid_layout = QGridLayout()
        self.image_container = QWidget()
        self.image_container.setLayout(self.grid_layout)
        self._ui.scrollArea.setWidget(self.image_container)

    def select_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Folder")
        if folder:
            self._ui.pathLabel.setText(f"Selected: {folder}")
            self.load_images(folder)
            # 🔧 Load images or trigger search here

    def load_images(self, folder):
        # Clear previous images
        for i in reversed(range(self.grid_layout.count())):
            widget = self.grid_layout.itemAt(i).widget()
            if widget:
                widget.setParent(None)

        # Add new images
        image_extensions = ('.png', '.jpg', '.jpeg', '.bmp', '.gif')
        files = [f for f in os.listdir(folder) if f.lower().endswith(image_extensions)]

        row = col = 0
        for idx, file in enumerate(files):
            path = os.path.join(folder, file)
            pixmap = QPixmap(path).scaled(150, 150, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            label = QLabel()
            label.setPixmap(pixmap)
            self.grid_layout.addWidget(label, row, col)
            col += 1
            if col >= 4:  # 4 columns
                col = 0
                row += 1


if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
