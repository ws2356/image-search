import sys
import os
import unittest
import time
import logging
from PySide6.QtWidgets import QApplication, QMenu
from PySide6.QtTest import QTest
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QClipboard

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import get_context
from dt_image_search.__main__ import MainWindow
from dt_image_search.index.index_worker import init_index_workers, deinit_index_workers
from dt_image_search.fs.bm_fs_monitor import start_watch, stop_watch
from dt_image_search.index.incremental_index_worker import init_incremental_index_workers, deinit_incremental_index_workers
from dt_image_search.index.dts_index import init as index_init
from dt_image_search.index.dts_model_downloader import init as model_downloader_init
from dt_image_search.model.dts_config import setup_model_cache
from dt_image_search.__main__ import MainWindow

# Setup logging
log_dir = os.path.dirname(__file__)
if not os.path.exists(log_dir):
    os.makedirs(log_dir)
log_file = os.path.join(log_dir, f"test_result_{time.strftime('%Y%m%d_%H%M%S')}.log")
logging.basicConfig(filename=log_file, level=logging.INFO, format='%(asctime)s %(message)s')

class TestGoldenPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not QApplication.instance():
            cls.app = QApplication(sys.argv)
        else:
            cls.app = QApplication.instance()

    def setUp(self):
        self.test_folder = os.path.abspath("tests/assets/test-folder")
        os.environ['UI_TEST'] = '1'
        os.environ['TEST_FOLDER'] = self.test_folder
        
        self.ctx = get_context()
        setup_model_cache(ctx=self.ctx)

        # Initialize background services
        model_downloader_init(self.ctx)
        index_init(self.ctx)
        init_incremental_index_workers(self.ctx)
        init_index_workers(self.ctx)
        start_watch(self.ctx)

        self.window = MainWindow(self.ctx)
        self.window.show()
        
        # Wait for window to be exposed
        QTest.qWait(1000)

    def tearDown(self):
        stop_watch()
        deinit_incremental_index_workers()
        deinit_index_workers()
        self.window.close()
        del self.window
        self.window.close()
        del self.window

    def test_golden_path(self):
        logging.info("Starting Golden Path Test")
        
        # Step 1: Wait for UI to stabilize
        QTest.qWait(1000)
        
        # Step 2: Remove folder if exists (Cleanup)
        # This would require iterating the tree model.
        # For this test, we assume a clean state or that adding it again is safe.
        # But the requirements explicitly say "remove it first".
        # Let's try to remove it if found.
        model = self.window.ui.folderTreeView.model()
        if model:
            # We need to find the item with data == test_folder
            # Since QStandardItemModel might be large, we'll check top level items.
            root = model.invisibleRootItem()
            found_item = None
            for i in range(root.rowCount()):
                item = root.child(i)
                # item.data(Qt.UserRole) returns the folder path
                if item.data(Qt.UserRole) == self.test_folder:
                    found_item = item
                    break
            
            if found_item:
                logging.info(f"Found existing folder {self.test_folder}, removing it.")
                # To remove, we need to trigger the context menu "Remove Folder" action.
                # We'll use the controller directly to simulate this action for reliability in setup phase.
                self.window.controller.on_delete_folder(found_item, self.test_folder)
                QTest.qWait(1000)

        # Step 3: Click Add Folder
        logging.info("Clicking Add Folder button")
        QTest.mouseClick(self.window.ui.addFolderButton, Qt.LeftButton)
        
        # Step 4: Wait for indexing completion
        logging.info("Waiting for indexing to complete")
        success = False
        # Wait up to 30 seconds
        for _ in range(60):
            msg = self.window.statusBar().currentMessage()
            if "Indexing completed" in msg:
                success = True
                logging.info(f"Indexing completed: {msg}")
                break
            QTest.qWait(500)
        
        self.assertTrue(success, "Indexing did not complete in 30 seconds")
        
        # Step 5: Type search query
        query = "wash machine" # filename is "wash machine.HEIC"
        logging.info(f"Typing search query: {query}")
        self.window.ui.searchInput.setFocus()
        QTest.keyClicks(self.window.ui.searchInput, query)
        
        # Step 6: Wait for search results
        logging.info("Waiting for search results")
        # Wait enough time for search to execute and update UI
        QTest.qWait(2000)
        
        view = self.window.ui.searchImageListView
        model = view.model()
        
        # Verify we have results
        self.assertIsNotNone(model)
        count = model.rowCount()
        logging.info(f"Found {count} results")
        self.assertGreater(count, 0, "No search results found")
        
        # Step 7: Right click first item and Copy File Path
        logging.info("Right clicking first result")
        index = model.index(0, 0)
        rect = view.visualRect(index)
        center = rect.center()
        
        # Mock QMenu.exec to automatically select "Copy File Path"
        original_exec = QMenu.exec
        
        def mock_exec(menu, pos=None):
            logging.info("Mock QMenu.exec called")
            # Find the "Copy File Path" action
            for action in menu.actions():
                if action.text() == "Copy File Path":
                    logging.info("Selecting 'Copy File Path' action")
                    return action
            return None
            
        QMenu.exec = mock_exec
        
        try:
            # Trigger context menu by calling the slot directly
            # This simulates the user right-clicking and the signal firing
            self.window.on_image_list_context_menu(center)
        finally:
            QMenu.exec = original_exec
            
        # Step 8: Assert clipboard content
        clipboard = QApplication.clipboard()
        text = clipboard.text()
        logging.info(f"Clipboard content: {text}")
        
        filename = os.path.basename(text)
        filename_no_ext = os.path.splitext(filename)[0]
        
        self.assertEqual(filename_no_ext, query)
        logging.info("Assertion passed: Clipboard content matches search query")
        
        # Step 9: Exit search mode
        logging.info("Exiting search mode")
        # Ensure search input has focus to receive key press
        self.window.ui.searchInput.setFocus()
        QTest.keyClick(self.window.ui.searchInput, Qt.Key_Escape)
        
        # Step 10: Repeat for other files if necessary (Not implemented for single file test)

if __name__ == "__main__":
    unittest.main()
