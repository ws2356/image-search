"""Start the PC-side instant share runtime with GUI mini window support.

Launches the mDNS advertised service daemon, bootstrap HTTP server, and
Qt-based mini window factory for manual end-to-end testing. When a mobile
device sends a bootstrap POST, the mini window pops up showing the
trust/transfer/delivery lifecycle.

Usage:
    python -m dt_image_search.scripts.start_instant_share_gui_runtime [--downloads-dir DIR]

The script runs until the window is closed or Ctrl+C is pressed. Requires
PySide6 (Qt) — uses the same QApplication as the main AuSearch app.

For headless testing without GUI, use `start_instant_share_runtime.py`.
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import sys
import time
from pathlib import Path

from PySide6.QtCore import QStandardPaths
from PySide6.QtWidgets import QApplication

from dt_image_search.instant_sharing import InstantShareRuntime
from dt_image_search.instant_sharing.mdns import INSTANT_SHARE_MDNS_SERVICE_TYPE, INSTANT_SHARE_MDNS_PORT
from dt_image_search.instant_sharing.mini_window_factory import InstantShareMiniWindowFactory
from dt_image_search.app_setting import initialize_app_settings

initialize_app_settings()

print(f"data dir reading from daemon: {QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation)}")

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Start the PC-side instant share runtime with GUI for manual testing."
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
        try:
            # 导入 macOS 原生 Cocoa 框架
            from AppKit import NSApplication, NSApplicationActivationPolicyProhibited
            
            # 获取当前运行的 App 实例
            ns_app = NSApplication.sharedApplication()
            # 设置激活策略为 Prohibited（完全不在 Dock 和菜单栏显示）
            ns_app.setActivationPolicy_(NSApplicationActivationPolicyProhibited)
            print("Hiding Dock icon on macOS...")
        except ImportError:
            print("警告: 缺少 pyobjc 库，无法动态隐藏 Dock 图标")

def main() -> int:
    args = _parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    _logger = logging.getLogger(__name__)

    print(f"Starting instant share runtime with GUI...")
    print(f"  mDNS service:      {INSTANT_SHARE_MDNS_SERVICE_TYPE}")
    print(f"  Image delivery:    {args.image_delivery_mode}")
    print(f"  Auto-receive:      enabled")
    if args.downloads_dir:
        print(f"  Downloads dir:     {args.downloads_dir}")
    else:
        print(f"  Downloads dir:     ~/Downloads (default)")

    # from dt_image_search.model.feature_flags import is_instant_share_enabled
    # if not args.force_enable and not is_instant_share_enabled():
    #     print("Instant Share feature is disabled by feature flag. Use --force-enable to bypass.")
    #     return 0

    # 1. 在初始化 GUI 之前，先戴上“隐形斗篷”
    hide_dock_icon()

    app = QApplication(sys.argv)
    app.setApplicationName("AuSearch Instant Share")

    mini_window_factory = InstantShareMiniWindowFactory()
    mini_window_factory.start()
    _logger.info("MiniWindowFactory started")

    runtime = InstantShareRuntime(
        is_enabled=lambda: True,
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
        auto_receive=True,
        pin_display_callback=mini_window_factory.show_pin,
    )

    started = runtime.start()
    if not started:
        print("Failed to start runtime.", file=sys.stderr)
        mini_window_factory.stop()
        return 1

    is_advertising = runtime.mdns_advertiser.is_advertising
    print(f"\nRuntime started.")
    print(f"  mDNS advertising: {is_advertising}")
    print(f"  HTTP server:      listening on port {runtime.http_server.port}")
    if not is_advertising:
        print(
            "  NOTE: advertising may become active in a few seconds.",
            file=sys.stderr,
        )

    stop_requested = False

    def _handle_signal(signum: int, frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True
        app.quit()

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    exit_code = app.exec()

    print("\nStopping runtime...")
    mini_window_factory.stop()
    runtime.stop()
    print("Stopped.")
    _logger.info("Test runtime exited")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
