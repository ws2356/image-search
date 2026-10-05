# Unit tests for the shell's URL swap loop (loading page → app URL, re-applied
# after every server restart announcement).
import queue
import threading
import unittest

from dt_image_search.shell.shell_main import run_url_swap


class FakeWindow:
    def __init__(self):
        self.urls = []
        self.htmls = []
        self.closed = False

    def load_url(self, url):
        if self.closed:
            raise RuntimeError("window destroyed")
        self.urls.append(url)

    def load_html(self, html):
        if self.closed:
            raise RuntimeError("window destroyed")
        self.htmls.append(html)


def _wait_until(predicate, timeout=5.0):
    deadline = threading.Event()
    while not predicate():
        if deadline.wait(timeout):
            break  # Event.wait returns False immediately; guard against hangs
    return predicate()


class TestRunUrlSwap(unittest.TestCase):
    def test_swaps_to_app_url_on_ready(self):
        ports = queue.Queue()
        ports.put(5173)
        window = FakeWindow()

        run_url_swap(ports, window, "tok", timeout=0.3)  # first port handled…

        self.assertEqual(window.urls, ["http://127.0.0.1:5173/?auth=tok"])

    def test_reapplies_url_after_server_restart(self):
        ports = queue.Queue()
        ports.put(5173)
        ports.put(5174)  # server crash → restart announces a NEW port
        window = FakeWindow()

        thread = threading.Thread(target=run_url_swap, args=(ports, window, "tok", 10), daemon=True)
        thread.start()
        self.assertTrue(_wait_until(lambda: len(window.urls) >= 2))
        ports.put(0)  # sentinel-ish: filler so the loop keeps running
        window.closed = True  # quit app → loop exits silently
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())

        self.assertEqual(window.urls, [
            "http://127.0.0.1:5173/?auth=tok",
            "http://127.0.0.1:5174/?auth=tok",
        ])

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
