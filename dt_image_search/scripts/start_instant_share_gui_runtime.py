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

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication, QLabel, QVBoxLayout, QWidget

from dt_image_search.instant_sharing import InstantShareRuntime
from dt_image_search.instant_sharing.mdns import INSTANT_SHARE_MDNS_SERVICE_TYPE, INSTANT_SHARE_MDNS_PORT
from dt_image_search.instant_sharing.mini_window_factory import InstantShareMiniWindowFactory
from dt_image_search.model.feature_flags import is_instant_share_enabled


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


def main() -> int:
    args = _parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    _logger = logging.getLogger(__name__)

    if not args.force_enable and not is_instant_share_enabled():
        print(
            "Instant share feature is disabled. Use --force-enable to start anyway.",
            file=sys.stderr,
        )
        return 1

    print(f"Starting instant share runtime with GUI...")
    print(f"  mDNS service:      {INSTANT_SHARE_MDNS_SERVICE_TYPE}")
    print(f"  Bootstrap endpoint: POST /api/instant-share/v1/sessions/bootstrap (port {INSTANT_SHARE_MDNS_PORT})")
    print(f"  Image delivery:    {args.image_delivery_mode}")
    print(f"  Auto-receive:      enabled (flow auto-starts on bootstrap)")
    if args.downloads_dir:
        print(f"  Downloads dir:     {args.downloads_dir}")
    else:
        print(f"  Downloads dir:     ~/Downloads (default)")

    app = QApplication(sys.argv)
    app.setApplicationName("AuSearch Instant Share Test")

    status_window = QWidget()
    status_window.setWindowTitle("Instant Share Runtime")
    status_window.resize(400, 120)
    layout = QVBoxLayout(status_window)
    status_label = QLabel(
        f"Instant Share runtime is active.\n"
        f"mDNS: {INSTANT_SHARE_MDNS_SERVICE_TYPE}\n"
        f"Bootstrap: port {INSTANT_SHARE_MDNS_PORT}\n"
        f"Waiting for mobile device to send bootstrap...\n"
    )
    status_label.setWordWrap(True)
    layout.addWidget(status_label)
    status_window.show()

    mini_window_factory = InstantShareMiniWindowFactory()
    mini_window_factory.start()
    _logger.info("MiniWindowFactory started")

    runtime = InstantShareRuntime(
        is_enabled=lambda: True,
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
        auto_receive=True,
    )

    started = runtime.start()
    if not started:
        print("Failed to start runtime.", file=sys.stderr)
        mini_window_factory.stop()
        return 1

    is_advertising = runtime.mdns_advertiser.is_advertising
    print(f"\nRuntime started.")
    print(f"  mDNS advertising: {is_advertising}")
    print(f"  Bootstrap HTTP:   listening on port {runtime.bootstrap_server.port}")
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

    def _periodic_check() -> None:
        nonlocal stop_requested
        if stop_requested:
            return
        active_session = runtime.session_registry.get_active_session()
        if active_session is not None:
            state = active_session.state.value
            status_label.setText(
                f"Instant Share runtime is active.\n"
                f"Session: {active_session.connection_config.session_id[:8]}...\n"
                f"State: {state}\n"
                f"Press Ctrl+C to stop.\n"
            )
        QTimer.singleShot(1000, _periodic_check)

    QTimer.singleShot(0, _periodic_check)

    exit_code = app.exec()

    print("\nStopping runtime...")
    mini_window_factory.stop()
    runtime.stop()
    print("Stopped.")
    _logger.info("Test runtime exited")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
