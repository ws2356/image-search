# Shell entrypoint (pywebview host, no Qt).
# Opens the window immediately with a loading page, swaps in the real URL
# once the index server announces its port, and hosts the pystray tray on
# platforms where it can run off the main thread.
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

    ready_event = threading.Event()
    port_holder = []

    def on_ready(port: int) -> None:
        port_holder.append(port)
        ready_event.set()

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
        if ready_event.wait(timeout=_READY_TIMEOUT_SECONDS) and port_holder:
            window.load_url(f"http://127.0.0.1:{port_holder[0]}/?auth={server.token}")
        else:
            window.load_html("AuSearch 启动失败,请重启应用。")

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
