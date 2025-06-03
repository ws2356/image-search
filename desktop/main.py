import sys
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog

from mainwindow_ui import Ui_MainWindow

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self._ui = Ui_MainWindow()
        self._ui.setupUi(self)
        # Connect button click to folder selection
        self._ui.selectButton.clicked.connect(self.select_folder)

    def select_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Folder")
        if folder:
            self._ui.pathLabel.setText(f"Selected: {folder}")
            # 🔧 Load images or trigger search here


if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
