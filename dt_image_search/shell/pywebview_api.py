# The JS API the web UI reaches through window.pywebview.api.
# Narrow surface on purpose: only the two system capabilities the UI needs
# (native folder picking, reveal in file manager). Trust boundary for file
# access lives in the index server; the shell just relays OS dialogs.
import os
import subprocess
import sys


class ShellApi:
    def __init__(self, webview_module=None):
        self._webview_module = webview_module

    def _webview(self):
        if self._webview_module is not None:
            return self._webview_module
        import webview

        return webview

    def pick_folder(self) -> str | None:
        """Open the native directory chooser; None when cancelled."""
        result = self._webview().create_file_dialog(self._webview().FOLDER_DIALOG)
        if result:
            return result[0]
        return None

    def reveal(self, file_path: str) -> None:
        """Reveal a file in the platform's file manager."""
        if sys.platform == "darwin":
            subprocess.run(["open", "-R", file_path], check=False)
        elif sys.platform == "win32":
            subprocess.run(["explorer", f"/select,{file_path}"], check=False)
        else:
            subprocess.run(["xdg-open", os.path.dirname(file_path) or file_path], check=False)
