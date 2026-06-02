"""Start the PC-side instant share runtime in standalone mode.

Launches the BLE service daemon and orchestrator for manual end-to-end testing
of the instant share flow with the iOS debug UI.

Usage:
    python -m dt_image_search.scripts.start_instant_share_runtime [--downloads-dir DIR]

The script runs until interrupted (Ctrl+C). It exposes the BLE GATT service
via the logical abstraction in dt_image_search.instant_sharing.ble and
handles incoming ConnectionConfig writes from mobile devices.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from dt_image_search.instant_sharing import InstantShareRuntime
from dt_image_search.instant_sharing.ble import (
    INSTANT_SHARE_GATT_SERVICE_NAME,
    INSTANT_SHARE_GATT_SERVICE_UUID,
    CONNECTION_CONFIG_CHARACTERISTIC,
    DEVICE_NAME_CHARACTERISTIC,
    DEVICE_SIGNATURE_CHARACTERISTIC,
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
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

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
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
    )

    started = runtime.start()
    if not started:
        print("Failed to start BLE daemon (feature flag disabled?).", file=sys.stderr)
        return 1

    print(f"\nRuntime started. Waiting for mobile connections...")
    print(f"Press Ctrl+C to stop.\n")

    stop_requested = False

    def _handle_signal(signum: int, frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    try:
        while not stop_requested:
            active_session = runtime.session_registry.get_active_session()
            if active_session is not None:
                state = active_session.state.value
                session_id = active_session.connection_config.session_id
                print(f"\r  Active session: {state:14s}  (id={session_id[:8]}...)", end="", flush=True)
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
