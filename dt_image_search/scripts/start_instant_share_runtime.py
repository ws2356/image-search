"""Start the PC-side instant share runtime in standalone mode.

Launches the BLE service daemon and orchestrator for manual end-to-end testing
of the instant share flow with the iOS debug UI.

Usage:
    python -m dt_image_search.scripts.start_instant_share_runtime [--downloads-dir DIR]

The script runs until interrupted (Ctrl+C). It exposes the BLE GATT service
via bless and handles incoming ConnectionConfig writes from mobile devices.
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

from dt_image_search.instant_sharing import InstantShareRuntime
from dt_image_search.instant_sharing.ble import (
    CONNECTION_CONFIG_CHARACTERISTIC,
    DEVICE_NAME_CHARACTERISTIC,
    DEVICE_SIGNATURE_CHARACTERISTIC,
    INSTANT_SHARE_GATT_SERVICE_NAME,
    INSTANT_SHARE_GATT_SERVICE_UUID,
)
from dt_image_search.model.feature_flags import is_instant_share_enabled


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Start the PC-side instant share runtime for manual testing."
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

    if not args.force_enable and not is_instant_share_enabled():
        print(
            "Instant share feature is disabled. Use --force-enable to start anyway.",
            file=sys.stderr,
        )
        return 1

    print(f"Starting instant share runtime...")
    print(f"  BLE service:       {INSTANT_SHARE_GATT_SERVICE_NAME} ({INSTANT_SHARE_GATT_SERVICE_UUID})")
    print(f"  DeviceName char:   {DEVICE_NAME_CHARACTERISTIC} (read-only)")
    print(f"  DeviceSignature:   {DEVICE_SIGNATURE_CHARACTERISTIC} (read-only)")
    print(f"  ConnectionConfig:  {CONNECTION_CONFIG_CHARACTERISTIC} (write-only)")
    print(f"  Image delivery:    {args.image_delivery_mode}")
    if args.downloads_dir:
        print(f"  Downloads dir:     {args.downloads_dir}")
    else:
        print(f"  Downloads dir:     ~/Downloads (default)")

    runtime = InstantShareRuntime(
        is_enabled=lambda: True,
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
    )

    started = runtime.start()
    if not started:
        print("Failed to start BLE daemon.", file=sys.stderr)
        last_error = runtime.ble_server.last_error
        if last_error is not None:
            print(f"  Last error: {type(last_error).__name__}: {last_error}", file=sys.stderr)
        return 1

    is_advertising = runtime.ble_server.is_advertising
    print(f"\nRuntime started. BLE advertising: {is_advertising}")
    if not is_advertising:
        last_error = runtime.ble_server.last_error
        if last_error is not None:
            print(f"  WARNING: advertising not active. Last error: {last_error}", file=sys.stderr)
        else:
            print(
                "  WARNING: advertising not active, but no error reported. "
                "Check System Settings > Bluetooth.",
                file=sys.stderr,
            )
    print(f"Press Ctrl+C to stop.\n")

    stop_requested = False

    def _handle_signal(signum: int, frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    try:
        last_ad_status = None
        while not stop_requested:
            ad_status = runtime.ble_server.is_advertising
            if ad_status != last_ad_status:
                logging.getLogger(__name__).info(
                    "BLE advertising status changed: %s -> %s",
                    last_ad_status,
                    ad_status,
                )
                last_ad_status = ad_status
            active_session = runtime.session_registry.get_active_session()
            if active_session is not None:
                state = active_session.state.value
                session_id = active_session.connection_config.session_id
                print(
                    f"\r  advertising={ad_status!s:5s}  active session: {state:14s}  (id={session_id[:8]}...)",
                    end="",
                    flush=True,
                )
            else:
                print(f"\r  advertising={ad_status!s:5s}  (no active session)        ", end="", flush=True)
            time.sleep(1.0)
    except KeyboardInterrupt:
        pass
    finally:
        print("\n\nStopping runtime...")
        runtime.stop()
        print("Stopped.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
