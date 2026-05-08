import os
import sys
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.__main__ import MainWindow, ctx
from dt_image_search.base.FolderTreeModel import FolderTreeModel


class TestMainWindowSectionExpansion(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._app = QApplication.instance() or QApplication([])

    def test_section_headers_are_expanded_after_init(self):
        window = MainWindow(ctx=ctx)
        try:
            self._app.processEvents()
            model = window.ui.browsePageFolderTreeView.model()

            section_indexes = []
            for row in range(model.rowCount()):
                index = model.index(row, 0)
                if bool(model.data(index, FolderTreeModel.SECTION_ROLE)):
                    section_indexes.append(index)

            self.assertGreaterEqual(len(section_indexes), 1)
            for index in section_indexes:
                self.assertTrue(window.ui.browsePageFolderTreeView.isExpanded(index))
        finally:
            window.close()


if __name__ == "__main__":
    unittest.main()
