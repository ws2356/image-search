# Unit tests for the shell's pywebview JS API and single-instance lock.
# Native dialog and subprocess calls are replaced at the OS boundary.
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import webview

from dt_image_search.shell.pywebview_api import ShellApi


class TestPickFolder(unittest.TestCase):
    def setUp(self):
        self.window = webview.Window("test", "AuSearch", url=None)
        self.window.gui = MagicMock()
        self.window.events.shown.set()
        self.api = ShellApi(window_provider=lambda: self.window)

    def test_returns_first_selection(self):
        self.window.gui.create_file_dialog.return_value = ("/selected/dir",)

        self.assertEqual(self.api.pick_folder(), "/selected/dir")
        self.window.gui.create_file_dialog.assert_called_once_with(
            webview.FOLDER_DIALOG, "", False, "", (), self.window.uid
        )

    def test_cancel_returns_none(self):
        self.window.gui.create_file_dialog.return_value = []
        self.assertIsNone(self.api.pick_folder())

    def test_js_none_returns_none(self):
        self.window.gui.create_file_dialog.return_value = None
        self.assertIsNone(self.api.pick_folder())


class TestReveal(unittest.TestCase):
    def test_macos_uses_open_R(self):
        api = ShellApi(window_provider=lambda: None)
        with patch('dt_image_search.shell.pywebview_api.sys.platform', 'darwin'), \
             patch('dt_image_search.shell.pywebview_api.subprocess.run') as mock_run:
            api.reveal("/photos/a.jpg")
        mock_run.assert_called_once_with(["open", "-R", "/photos/a.jpg"], check=False)

    def test_windows_uses_explorer_select(self):
        api = ShellApi(window_provider=lambda: None)
        with patch('dt_image_search.shell.pywebview_api.sys.platform', 'win32'), \
             patch('dt_image_search.shell.pywebview_api.subprocess.run') as mock_run:
            api.reveal("/photos/a.jpg")
        mock_run.assert_called_once_with(["explorer", "/select,/photos/a.jpg"], check=False)

    def test_linux_opens_parent_directory(self):
        api = ShellApi(window_provider=lambda: None)
        with patch('dt_image_search.shell.pywebview_api.sys.platform', 'linux'), \
             patch('dt_image_search.shell.pywebview_api.subprocess.run') as mock_run:
            api.reveal("/photos/a.jpg")
        mock_run.assert_called_once_with(["xdg-open", "/photos"], check=False)


class TestSingleInstanceLock(unittest.TestCase):
    def test_second_acquire_fails_until_release(self):
        from dt_image_search.shell.single_instance import acquire_instance_lock, release_instance_lock

        with tempfile.TemporaryDirectory() as temp_dir:
            lock_path = os.path.join(temp_dir, "shell_instance.lock")
            handle = acquire_instance_lock(lock_path)
            self.assertIsNotNone(handle)
            self.assertIsNone(acquire_instance_lock(lock_path))  # double open blocked
            release_instance_lock(handle)
            reacquired = acquire_instance_lock(lock_path)
            self.assertIsNotNone(reacquired)
            release_instance_lock(reacquired)


if __name__ == "__main__":
    unittest.main()
