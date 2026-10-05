# Shell entrypoint (pywebview host, no Qt).
# Opens the window immediately with a loading page, swaps in the real URL
# once the index server announces its port, and hosts the pystray tray on
# platforms where it can run off the main thread.
import queue
import sys
import threading

from dt_image_search.shell.pywebview_api import ShellApi
from dt_image_search.shell.server_process import ServerProcess
from dt_image_search.shell.single_instance import acquire_instance_lock, release_instance_lock
from pc_common.telemetry.telemetry_client import log

_LOADING_HTML = (
    "<html><body style='display:flex;align-items:center;justify-content:center;"
    "height:100vh;font-family:sans-serif;color:#606266;'>"
    "AuSearch 正在启动…</body></html>"
)

_READY_TIMEOUT_SECONDS = 60


def run_url_swap(port_queue, window, token: str, timeout: float = _READY_TIMEOUT_SECONDS) -> None:
    """Swap the loading page for the app URL; re-applied after every server
    restart announcement (each restart binds a new ephemeral port)."""
    import queue as _queue

    while True:
        try:
            port = port_queue.get(timeout=timeout)
        except _queue.Empty:
            window.load_html("AuSearch 启动失败,请重启应用。")
            return
        try:
            window.load_url(f"http://127.0.0.1:{port}/?auth={token}")
        except Exception:
            return  # window destroyed (quit) — stop swapping


def main() -> None:
    import argparse
    import webview

    parser = argparse.ArgumentParser(description="AuSearch web shell")
    parser.add_argument("--static-dir", default=None, help="Passed through to the index server (optional)")
    args = parser.parse_args()

    server_args = []
    if args.static_dir:
        server_args += ["--static-dir", args.static_dir]

    lock_handle = acquire_instance_lock(str(_lock_path()))
    if lock_handle is None:
        log("error", message="shell_main: another instance is already running")
        return

    ready_ports: queue.Queue = queue.Queue()

    def on_ready(port: int) -> None:
        ready_ports.put(port)

    def on_exit() -> None:
        # Server gave up; close the window so the process exits.
        try:
            window.destroy()
        except Exception:
            pass

    server = ServerProcess(on_ready=on_ready, on_exit=on_exit, extra_args=server_args)
    server.start()

    window = webview.create_window(
        "AuSearch",
        url=f"data:text/html;charset=utf-8,{_LOADING_HTML}",
        js_api=ShellApi(),
        width=1280,
        height=800,
    )

    def swap_to_app() -> None:
        run_url_swap(ready_ports, window, server.token)

    threading.Thread(target=swap_to_app, daemon=True).start()

    if sys.platform != "darwin":
        _start_tray(show_window=lambda: window.show(), quit_app=lambda: (server.stop(), window.destroy()))

    try:
        webview.start()
    finally:
        server.stop()
        release_instance_lock(lock_handle)


def _lock_path():
    from pc_common.model.dts_fs import get_app_data_path

    return get_app_data_path() / "shell_instance.lock"


def _start_tray(show_window, quit_app) -> None:
    import pystray
    from PIL import Image, ImageDraw

    icon_image = Image.new("RGB", (64, 64), (64, 158, 255))
    draw = ImageDraw.Draw(icon_image)
    draw.ellipse((16, 16, 48, 48), fill=(255, 255, 255))

    menu = pystray.Menu(
        pystray.MenuItem("显示窗口", lambda *_: show_window(), default=True),
        pystray.MenuItem("退出", lambda *_: quit_app()),
    )
    tray = pystray.Icon("ausearch", icon_image, "AuSearch", menu)
    threading.Thread(target=tray.run, daemon=True).start()


if __name__ == "__main__":
    main()
