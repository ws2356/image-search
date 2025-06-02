import sys
from PySide6.QtWidgets import QApplication, QMainWindow
from ui_main import Ui_MainWindow

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)
        self.ui.search_button.clicked.connect(self.run_search)

    def run_search(self):
        query = self.ui.query_input.text()
        print(f"Running search for: {query}")
        # You can call search_engine.search(query) here

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = MainWindow()
    window.setWindowTitle("Image Search App")
    window.resize(600, 400)
    window.show()
    sys.exit(app.exec())
