#!/usr/bin/env python3
"""
Temporary test script to verify global exception handlers work correctly.
This file can be deleted after testing.
"""

import sys
import os
import threading
import time

# Add the parent directory to sys.path to import dt_image_search modules
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from PySide6.QtWidgets import QApplication, QPushButton, QVBoxLayout, QWidget
from PySide6.QtCore import QTimer, qDebug, qWarning, qCritical
from dt_image_search.telemetry.telemetry_client import log


class ExceptionTestWidget(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Exception Handler Tests")
        self.setGeometry(100, 100, 300, 400)
        
        layout = QVBoxLayout()
        
        # Test buttons for different exception types
        btn1 = QPushButton("Test Python Exception (Main Thread)")
        btn1.clicked.connect(self.test_python_exception)
        layout.addWidget(btn1)
        
        btn2 = QPushButton("Test Threading Exception")
        btn2.clicked.connect(self.test_threading_exception)
        layout.addWidget(btn2)
        
        btn3 = QPushButton("Test Qt Debug Message")
        btn3.clicked.connect(self.test_qt_debug)
        layout.addWidget(btn3)
        
        btn4 = QPushButton("Test Qt Warning")
        btn4.clicked.connect(self.test_qt_warning)
        layout.addWidget(btn4)
        
        btn5 = QPushButton("Test Qt Critical")
        btn5.clicked.connect(self.test_qt_critical)
        layout.addWidget(btn5)
        
        btn6 = QPushButton("Test Division by Zero")
        btn6.clicked.connect(self.test_division_by_zero)
        layout.addWidget(btn6)
        
        btn7 = QPushButton("Test Index Error")
        btn7.clicked.connect(self.test_index_error)
        layout.addWidget(btn7)
        
        btn8 = QPushButton("Test Delayed Exception (5 seconds)")
        btn8.clicked.connect(self.test_delayed_exception)
        layout.addWidget(btn8)
        
        btn9 = QPushButton("Test Import Error Simulation")
        btn9.clicked.connect(self.test_import_error)
        layout.addWidget(btn9)
        
        self.setLayout(layout)
    
    def test_python_exception(self):
        """Test uncaught Python exception in main thread"""
        print("About to raise ValueError in main thread...")
        raise ValueError("This is a test ValueError from main thread")
    
    def test_threading_exception(self):
        """Test uncaught exception in background thread"""
        def worker_function():
            print("Background thread about to raise exception...")
            time.sleep(1)  # Small delay to see the thread start
            raise RuntimeError("This is a test RuntimeError from background thread")
        
        thread = threading.Thread(target=worker_function, name="TestWorkerThread")
        thread.start()
        print("Started background thread that will raise exception...")
    
    def test_qt_debug(self):
        """Test Qt debug message"""
        qDebug("This is a test Qt debug message")
        print("Sent Qt debug message")
    
    def test_qt_warning(self):
        """Test Qt warning message"""
        qWarning("This is a test Qt warning message")
        print("Sent Qt warning message")
    
    def test_qt_critical(self):
        """Test Qt critical message"""
        qCritical("This is a test Qt critical message")
        print("Sent Qt critical message")
    
    def test_division_by_zero(self):
        """Test division by zero exception"""
        print("About to divide by zero...")
        result = 10 / 0
        print(f"Result: {result}")  # This won't be reached
    
    def test_index_error(self):
        """Test index error exception"""
        print("About to access invalid list index...")
        my_list = [1, 2, 3]
        value = my_list[10]
        print(f"Value: {value}")  # This won't be reached
    
    def test_delayed_exception(self):
        """Test exception after a delay using QTimer"""
        print("Will raise exception in 5 seconds...")
        QTimer.singleShot(5000, self.delayed_exception_handler)
    
    def delayed_exception_handler(self):
        """Handler for delayed exception"""
        print("5 seconds passed, raising exception now...")
        raise TimeoutError("This is a delayed TimeoutError")
    
    def test_import_error(self):
        """Simulate an import error"""
        print("About to simulate import error...")
        # This will cause an ImportError
        import nonexistent_module_12345


def main():
    """Main function to set up the test application"""
    # Import and set up the exception handlers from your main module
    from dt_image_search.__main__ import (
        handle_python_exception, 
        handle_threading_exception,
        qt_message_handler
    )
    
    # Install exception handlers
    sys.excepthook = handle_python_exception
    
    if hasattr(threading, 'excepthook'):
        threading.excepthook = handle_threading_exception
    
    app = QApplication(sys.argv)
    
    # Install Qt message handler
    from PySide6.QtCore import qInstallMessageHandler
    qInstallMessageHandler(qt_message_handler)
    
    # Create and show the test widget
    widget = ExceptionTestWidget()
    widget.show()
    
    print("Exception Handler Test Application Started")
    print("Click buttons to test different types of exceptions")
    print("Check console output and telemetry logs")
    print("Press Ctrl+C to exit gracefully")
    
    # Run the application
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
