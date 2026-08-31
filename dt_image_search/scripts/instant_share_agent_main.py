"""Start the PC-side instant share runtime with GUI mini window support.

Launches the mDNS advertised service daemon, bootstrap HTTP server, and
Qt-based mini window factory for manual end-to-end testing. When a mobile
device sends a bootstrap POST, the mini window pops up showing the
trust/transfer/delivery lifecycle.

Usage:
    python -m dt_image_search.scripts.instant_share_agent_main [--downloads-dir DIR]

The script runs until the window is closed or Ctrl+C is pressed. Requires
PySide6 (Qt) — uses the same QApplication as the main AuSearch app.

For headless testing without GUI, use `instant_share_agent_main.py`.
"""

from __future__ import annotations

import argparse
import faulthandler
import logging
import os
import signal
import sys
import threading
import time
import traceback
import uuid
from pathlib import Path

from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QTimer

from dt_image_search.dts_logging import get_other_handlers
from instant_sharing import InstantShareRuntime
from instant_sharing.mdns import INSTANT_SHARE_MDNS_SERVICE_TYPE
from instant_sharing.mini_window_factory import InstantShareMiniWindowFactory
from instant_sharing.qr_trigger_mini_window_factory import QRTriggerMiniWindowFactory
from dt_image_search.model.dt_device_id import get_device_id
from dt_image_search.model.dts_config import get_log_level, get_revision
from dt_image_search.model.feature_flags import get_desktop_root_trace_sample_rate
from dt_image_search.telemetry.runtime_metadata import RESOURCE_ATTRIBUTES
from dt_image_search.telemetry.telemetry_client import (
    flush_telemetry,
    flush_telemetry_for_fatal,
    init_telemetry,
    log,
)
from dt_image_search.tools.dt_is_debug import is_debug

_WHERE = "instant_share.agent_main"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Start the PC-side Snap Get runtime with GUI for manual testing."
    )
    parser.add_argument(
        "--downloads-dir",
        type=Path,
        default=None,
        help="Directory where image payloads will be saved. Defaults to ~/Downloads.",
    )
    parser.add_argument(
        "--image-delivery-mode",
        choices=["file", "clipboard"],
        default="file",
        help="How image payloads are delivered. Defaults to 'file'.",
    )
    parser.add_argument(
        "--force-enable",
        action="store_true",
        help="Bypass the feature flag check and start the runtime regardless.",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity. Defaults to INFO.",
    )
    return parser.parse_args()


def hide_dock_icon():
    """动态隐藏当前进程在 macOS Dock 栏的图标"""
    if sys.platform == "darwin":
        # 导入 macOS 原生 Cocoa 框架
        from AppKit import NSApplication, NSApplicationActivationPolicyAccessory

        # 获取当前运行的 App 实例
        ns_app = NSApplication.sharedApplication()
        # 设置激活策略为 Accessory（在 Dock 和菜单栏中隐藏，但仍可接收事件）
        ns_app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)


def _install_crash_hooks() -> None:
    """Report uncaught exceptions (main + threads) through telemetry.

    The launch agent is restarted silently by launchd, so without these hooks
    a crashing agent would be invisible on the telemetry side.
    """

    def _handle_python_exception(exc_type, exc_value, exc_traceback):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_traceback)
            return
        error_msg = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        log(
            "error",
            error_type="agent.uncaught_exception",
            message=error_msg,
            where=_WHERE,
        )
        flush_telemetry_for_fatal()
        sys.__excepthook__(exc_type, exc_value, exc_traceback)

    def _handle_threading_exception(args):
        exc_type, exc_value, exc_traceback, thread = args
        error_msg = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        thread_name = thread.name if thread else "Unknown"
        log(
            "error",
            error_type="agent.thread_exception",
            message=error_msg,
            where=f"{_WHERE}.{thread_name}",
        )
        flush_telemetry_for_fatal()

    sys.excepthook = _handle_python_exception
    if hasattr(threading, "excepthook"):
        threading.excepthook = _handle_threading_exception


def _log_agent_startup(args: argparse.Namespace) -> None:
    log(
        "info",
        message="instant-share agent starting",
        where=f"{_WHERE}.main",
        attributes={
            "instant_share.pid": os.getpid(),
            "instant_share.ppid": os.getppid(),
            "instant_share.argv": sys.argv[1:],
            "instant_share.image_delivery_mode": args.image_delivery_mode,
            "instant_share.downloads_dir": str(args.downloads_dir) if args.downloads_dir else "",
            "instant_share.mdns_service_type": INSTANT_SHARE_MDNS_SERVICE_TYPE,
        },
    )


class _AgentHeartbeat:
    """Rate-limited heartbeat distinguishing 'agent alive' from 'sock missing'.

    The BLE daemon invokes the callback on a fast poll loop; emission is
    capped at one telemetry record per interval.
    """

    _INTERVAL_SECONDS = 300.0

    def __init__(self) -> None:
        self._runtime: InstantShareRuntime | None = None
        self._started_at = time.monotonic()
        self._last_emit = 0.0

    def attach(self, runtime: InstantShareRuntime) -> None:
        self._runtime = runtime

    def __call__(self) -> None:
        now = time.monotonic()
        if now - self._last_emit < self._INTERVAL_SECONDS:
            return
        self._last_emit = now
        unix_server = self._runtime.unix_socket_server if self._runtime is not None else None
        socket_path = unix_server.socket_path if unix_server is not None else None
        log(
            "info",
            message="instant-share agent heartbeat",
            where=f"{_WHERE}.heartbeat",
            attributes={
                "instant_share.uptime_seconds": round(now - self._started_at, 1),
                "instant_share.unix_socket_running": (
                    unix_server.is_running if unix_server is not None else False
                ),
                "instant_share.socket_exists": (
                    bool(socket_path is not None and socket_path.exists())
                ),
                "instant_share.socket_path": str(socket_path) if socket_path is not None else "",
            },
        )


def main() -> int:

    args = _parse_args()

    # Telemetry is entry-point-wired: the launch agent passes its own values so
    # telemetry_client carries no app-storage dependencies. Resolving paths
    # here (before QApplication sets the app name) matches the main app's
    # QStandardPaths lifecycle.
    init_telemetry(
        device_id=get_device_id(),
        session_id=str(uuid.uuid4()),
        revision=get_revision(),
        log_level=get_log_level(),
        root_trace_sample_rate=get_desktop_root_trace_sample_rate(),
        resource_attributes=RESOURCE_ATTRIBUTES,
        log_handlers=get_other_handlers(),
        debug_mode=is_debug(),
    )

    app = QApplication(sys.argv)
    app.setOrganizationDomain("net.boldman")
    app.setApplicationName("SnapGet")
    app.setQuitOnLastWindowClosed(False)

    _install_crash_hooks()
    _log_agent_startup(args)

    # 1. 在初始化 GUI 之后，戴上“隐形斗篷”
    hide_dock_icon()

    mini_window_factory = InstantShareMiniWindowFactory()
    mini_window_factory.start()
    log("info", message="MiniWindowFactory started", where=f"{_WHERE}.main")

    heartbeat = _AgentHeartbeat()
    runtime = InstantShareRuntime(
        is_enabled=lambda: True,
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
        auto_receive=True,
        pin_display_callback=mini_window_factory.show_pin,
        heartbeat=heartbeat,
    )
    heartbeat.attach(runtime)

    started = runtime.start()
    if not started:
        log(
            "error",
            error_type="agent.start_failed",
            message="Failed to start instant-share runtime; agent will exit (launchd will restart it)",
            where=f"{_WHERE}.main",
        )
        flush_telemetry_for_fatal()
        mini_window_factory.stop()
        return 1

    qr_window_factory = QRTriggerMiniWindowFactory(
        runtime.qr_trigger_handler,
        device_id=runtime.device_id,
        pc_port=runtime.http_server.port,
        pc_tls_port=runtime.tls_server.port,
    )
    qr_window_factory.start()
    log("info", message="QRTriggerMiniWindowFactory started", where=f"{_WHERE}.main")

    log(
        "info",
        message="instant-share runtime ready",
        where=f"{_WHERE}.main",
        attributes={
            "instant_share.mdns_advertising": runtime.mdns_advertiser.is_advertising,
            "instant_share.http_port": runtime.http_server.port,
            "instant_share.tls_port": runtime.tls_server.port,
        },
    )

    stop_requested = False

    def _handle_signal(signum: int, frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True
        try:
            signal_name = signal.Signals(signum).name
        except ValueError:
            signal_name = str(signum)
        log(
            "info",
            message="agent stop signal received",
            where=f"{_WHERE}._handle_signal",
            attributes={"instant_share.signal": signal_name},
        )
        app.quit()

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    signal_timer = QTimer()
    signal_timer.start(2000)
    signal_timer.timeout.connect(lambda: None)

    exit_code = app.exec()

    log(
        "info",
        message="instant-share agent exiting",
        where=f"{_WHERE}.main",
        attributes={
            "instant_share.exit_code": exit_code,
            "instant_share.stop_requested": stop_requested,
        },
    )
    qr_window_factory.stop()
    mini_window_factory.stop()
    runtime.stop()
    flush_telemetry()
    log("info", message="agent stopped", where=f"{_WHERE}.main")

    return exit_code


if __name__ == "__main__":
    try:
        faulthandler.register(signal.SIGUSR1, all_threads=True)
    except Exception:
        pass

    sys.exit(main())
