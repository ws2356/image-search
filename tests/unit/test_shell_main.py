# Unit tests for the shell's URL swap loop (loading page → app URL, re-applied
# after every server restart announcement).
import queue
import subprocess
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from dt_image_search.shell.shell_main import run_url_swap


class TestShellEntrypoint(unittest.TestCase):
    def test_default_launcher_module_supports_help_without_starting_a_server(self):
        result = subprocess.run(
            [sys.executable, "-m", "dt_image_search.shell", "--help"],
            cwd=Path(__file__).resolve().parents[2],
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--static-dir", result.stdout)

    def test_window_creation_failure_still_releases_instance_lock(self):
        from dt_image_search.shell.shell_main import main

        webview = MagicMock()
        webview.create_window.side_effect = RuntimeError("no display")
        with (
            patch.dict(sys.modules, {"webview": webview}),
            patch.object(sys, "argv", ["shell"]),
            patch("dt_image_search.shell.shell_main.init_desktop_telemetry"),
            patch("dt_image_search.shell.shell_main.acquire_instance_lock", return_value=42),
            patch("dt_image_search.shell.shell_main.release_instance_lock") as release,
            patch("dt_image_search.shell.shell_main._lock_path", return_value=Path("/unused")),
            patch("dt_image_search.shell.shell_main.ServerProcess") as server,
        ):
            with self.assertRaisesRegex(RuntimeError, "no display"):
                main()
        release.assert_called_once_with(42)
        server.return_value.stop.assert_called_once()
        server.return_value.start.assert_not_called()


class FakeWindow:
    def __init__(self):
        self.urls = []
        self.htmls = []
        self.closed = False
        self.url_loaded = threading.Event()

    def load_url(self, url):
        if self.closed:
            raise RuntimeError("window destroyed")
        self.urls.append(url)
        self.url_loaded.set()

    def load_html(self, html):
        if self.closed:
            raise RuntimeError("window destroyed")
        self.htmls.append(html)


class TestRunUrlSwap(unittest.TestCase):
    def test_swaps_to_app_url_on_ready(self):
        ports = queue.Queue()
        ports.put(5173)
        ports.put(None)
        window = FakeWindow()

        run_url_swap(ports, window, "tok", timeout=0.3)

        self.assertEqual(window.urls, ["http://127.0.0.1:5173/?auth=tok"])
        self.assertEqual(window.htmls, [])

    def test_reapplies_url_after_server_restart(self):
        ports = queue.Queue()
        ports.put(5173)
        ports.put(5174)  # server crash → restart announces a NEW port
        ports.put(None)
        window = FakeWindow()

        run_url_swap(ports, window, "tok", timeout=0.3)

        self.assertEqual(window.urls, [
            "http://127.0.0.1:5173/?auth=tok",
            "http://127.0.0.1:5174/?auth=tok",
        ])
        self.assertEqual(window.htmls, [])

    def test_healthy_app_survives_startup_timeout_and_later_restart(self):
        ports = queue.Queue()
        ports.put(5173)
        window = FakeWindow()
        finished = threading.Event()

        def swap():
            try:
                run_url_swap(ports, window, "tok", timeout=0.02)
            finally:
                finished.set()

        thread = threading.Thread(target=swap, daemon=True)
        thread.start()
        try:
            self.assertTrue(window.url_loaded.wait(1))
            self.assertFalse(finished.wait(0.1))
            self.assertEqual(window.htmls, [])
            window.url_loaded.clear()
            ports.put(5174)
            self.assertTrue(window.url_loaded.wait(1))
            self.assertEqual(window.urls[-1], "http://127.0.0.1:5174/?auth=tok")
        finally:
            ports.put(None)
            thread.join(timeout=1)
        self.assertFalse(thread.is_alive())

    def test_exit_before_ready_does_not_show_startup_error(self):
        ports = queue.Queue()
        ports.put(None)
        window = FakeWindow()

        run_url_swap(ports, window, "tok", timeout=0.02)

        self.assertEqual(window.urls, [])
        self.assertEqual(window.htmls, [])

    def test_shows_error_after_timeout_without_ready(self):
        window = FakeWindow()
        ports = queue.Queue()

        run_url_swap(ports, window, "tok", timeout=0.2)

        self.assertEqual(window.urls, [])
        self.assertEqual(window.htmls, ["AuSearch 启动失败,请重启应用。"])

    def test_returns_silently_when_window_already_destroyed(self):
        ports = queue.Queue()
        ports.put(5173)
        window = FakeWindow()
        window.closed = True

        run_url_swap(ports, window, "tok", timeout=1)

        self.assertEqual(window.urls, [])  # no crash after quit


if __name__ == "__main__":
    unittest.main()
