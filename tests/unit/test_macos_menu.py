"""Verify window recovery through the public pywebview menu action.

Author: Codex
Created: 2026-11-13
"""
import unittest
from unittest.mock import Mock, call

from dt_image_search.shell.macos_menu import create_window_menu


class TestMacOSMenu(unittest.TestCase):
    def test_show_action_restores_and_shows_the_window(self):
        window = Mock()
        menus = create_window_menu(window)
        self.assertEqual(len(menus), 1)
        self.assertEqual(len(menus[0].items), 1)
        menus[0].items[0].function()
        self.assertEqual(window.method_calls, [
            call.restore(),
            call.show(),
        ])


if __name__ == "__main__":
    unittest.main()
