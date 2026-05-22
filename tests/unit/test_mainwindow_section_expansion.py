import os
import sys
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.__main__ import MainWindow, ctx, maybe_show_startup_update_prompt
from dt_image_search.base.FolderTreeModel import FolderTreeModel
from dt_image_search.model.feature_flags import DesktopVersionFlag


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

    def test_startup_update_prompt_uses_existing_dialog_signal(self):
        window = MainWindow(ctx=ctx)
        try:
            window.show_update_prompt_signal.disconnect()
            emitted_prompts: list[tuple[bool, str, str]] = []
            window.show_update_prompt_signal.connect(
                lambda required, body_text, update_destination: emitted_prompts.append(
                    (required, body_text, update_destination)
                )
            )
            with patch(
                "dt_image_search.__main__.get_version_update_requirement",
                return_value=DesktopVersionFlag(min_version="2.3.4", required=True),
            ):
                maybe_show_startup_update_prompt(window, current_version="1.0.0")

            self.assertEqual(
                emitted_prompts,
                [
                    (
                        True,
                        "AuSearch 2.3.4 or later is required to continue. Update now to keep using the app.",
                        "",
                    )
                ],
            )
        finally:
            window.close()

    def test_startup_update_prompt_skips_when_no_update_is_required(self):
        window = MainWindow(ctx=ctx)
        try:
            window.show_update_prompt_signal.disconnect()
            emitted_prompts: list[tuple[bool, str, str]] = []
            window.show_update_prompt_signal.connect(
                lambda required, body_text, update_destination: emitted_prompts.append(
                    (required, body_text, update_destination)
                )
            )
            with patch(
                "dt_image_search.__main__.get_version_update_requirement",
                return_value=None,
            ):
                maybe_show_startup_update_prompt(window, current_version="1.0.0")

            self.assertEqual(emitted_prompts, [])
        finally:
            window.close()


if __name__ == "__main__":
    unittest.main()
