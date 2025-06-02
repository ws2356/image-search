from PySide6.QtWidgets import QMainWindow, QWidget, QLabel, QLineEdit, QPushButton, QVBoxLayout

class Ui_MainWindow(object):
    def setupUi(self, MainWindow):
        self.central_widget = QWidget(MainWindow)

        self.query_label = QLabel("Enter search text:")
        self.query_input = QLineEdit()
        self.search_button = QPushButton("Search")

        self.layout = QVBoxLayout(self.central_widget)
        self.layout.addWidget(self.query_label)
        self.layout.addWidget(self.query_input)
        self.layout.addWidget(self.search_button)

        MainWindow.setCentralWidget(self.central_widget)
