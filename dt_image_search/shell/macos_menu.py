"""Add window recovery to pywebview's native Cocoa application menus.

Author: Codex
Created: 2026-11-13
"""
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from webview import Window
    from webview.menu import Menu


def create_window_menu(window: "Window") -> list["Menu"]:
    """Keep native About/Quit actions and add access to a hidden/minimized window."""
    from webview.menu import Menu, MenuAction

    def show_window() -> None:
        window.restore()
        window.show()

    # Cocoa already supplies About and Quit (including Cmd+Q and close events).
    # Use its public menu API so pywebview retains ownership of AppKit delegates.
    return [Menu("窗口", [MenuAction("显示窗口", show_window)])]
