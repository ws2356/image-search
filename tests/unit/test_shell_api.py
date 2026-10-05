# Unit tests for the shell's pywebview JS API and single-instance lock.
# webview module is faked; subprocess calls are monkeypatched per platform.
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from dt_image_search.shell.pywebview_api import ShellApi


class _FakeWebviewModule:
    FOLDER_DIALOG = 33

    def __init__(self, dialog_result=None):
        self.FOLDER_DIALOG = _FakeWebviewModule.FOLDER_DIALOG
        self._dialog_result = dialog_result
        self.calls = []

    def create_file_dialog(self, dialog_type):
        self.calls.append(dialog_type)
        return self._dialog_result


class TestPickFolder(unittest.TestCase):
    def test_returns_first_selection(self):
        fake = _FakeWebviewModule(dialog_result=["/selected/dir"])
        api = ShellApi(webview_module=fake)
        self.assertEqual(api.pick_folder(), "/selected/dir")
        self.assertEqual(fake.calls, [_FakeWebviewModule.FOLDER_DIALOG])

    def test_cancel_returns_none(self):
        fake = _FakeWebviewModule(dialog_result=[])
        api = ShellApi(webview_module=fake)
        self.assertIsNone(api.pick_folder())

    def test_js_none_returns_none(self):
        # pywebview passes JS undefined through as None in some versions.
        fake = _FakeWebviewModule(dialog_result=None)
        api = ShellApi(webview_module=fake)
        self.assertIsNone(api.pick_folder())


class TestReveal(unittest.TestCase):
    def test_macos_uses_open_R(self):
        api = ShellApi(webview_module=_FakeWebviewModule())
        with patch('dt_image_search.shell.pywebview_api.sys.platform', 'darwin'), \
             patch('dt_image_search.shell.pywebview_api.subprocess.run') as mock_run:
            api.reveal("/photos/a.jpg")
        mock_run.assert_called_once_with(["open", "-R", "/photos/a.jpg"], check=False)

    def test_windows_uses_explorer_select(self):
        api = ShellApi(webview_module=_FakeWebviewModule())
        with patch('dt_image_search.shell.pywebview_api.sys.platform', 'win32'), \
             patch('dt_image_search.shell.pywebview_api.subprocess.run') as mock_run:
            api.reveal("/photos/a.jpg")
        mock_run.assert_called_once_with(["explorer", "/select,/photos/a.jpg"], check=False)

    def test_linux_opens_parent_directory(self):
        api = ShellApi(webview_module=_FakeWebviewModule())
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
