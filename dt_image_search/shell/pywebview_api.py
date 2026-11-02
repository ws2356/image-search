# The JS API the web UI reaches through window.pywebview.api.
# Narrow surface on purpose: only the two system capabilities the UI needs
# (native folder picking, reveal in file manager). Trust boundary for file
# access lives in the index server; the shell just relays OS dialogs.
import os
import subprocess
import sys
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from webview import Window


class ShellApi:
    def __init__(self, window_provider: Callable[[], "Window"]):
        self._window_provider = window_provider

    def pick_folder(self) -> str | None:
        """Open the native directory chooser; None when cancelled."""
        import webview

        result = self._window_provider().create_file_dialog(webview.FOLDER_DIALOG)
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
