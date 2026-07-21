"""
Network change monitor using macOS SystemConfiguration framework.
Detects IP address changes on macOS and publishes events via dts_event_bus.

Author: Agent
Date: 2026-06-21
"""

from __future__ import annotations

import logging
import sys
import threading

_logger = logging.getLogger(__name__)

# Conditionally import macOS-specific frameworks
_HAS_NATIVE_MONITOR = False
if sys.platform == "darwin":
    try:
        from SystemConfiguration import (  # type: ignore[import-untyped]
            SCDynamicStoreCreate,
            SCDynamicStoreCreateRunLoopSource,
            SCDynamicStoreSetNotificationKeys,
        )
        from CoreFoundation import (  # type: ignore[import-untyped]
            CFRunLoopAddSource,
            CFRunLoopGetCurrent,
            CFRunLoopRunInMode,
            kCFRunLoopDefaultMode,
        )
        _HAS_NATIVE_MONITOR = True
    except ImportError as exc:
        _logger.warning(
            "NetworkMonitor: pyobjc-framework-SystemConfiguration not available: %s",
            exc,
        )


class NetworkMonitor:
    """Monitors macOS network configuration changes and detects IP address changes.

    Uses SystemConfiguration.framework via pyobjc for zero-polling,
    kernel-driven notifications. Maintains an internal snapshot of LAN
    IPv4 addresses and publishes ``is.network.ip_changed`` on the default
    event bus when the set changes.

    On non-macOS platforms, all methods are no-ops.
    """

    def __init__(self) -> None:
        self._ip_snapshot: set[str] = set()
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.RLock()

    @property
    def is_running(self) -> bool:
        with self._lock:
            thread = self._thread
        return thread is not None and thread.is_alive()

    @property
    def current_ips(self) -> set[str]:
        with self._lock:
            return set(self._ip_snapshot)

    def start(self) -> None:
        """Start monitoring network changes on a daemon thread.

        On non-macOS platforms this is a no-op.
        """
        if not _HAS_NATIVE_MONITOR:
            _logger.debug("NetworkMonitor: not on macOS or frameworks unavailable, skipping")
            return

        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                _logger.info("NetworkMonitor: already running")
                return

            self._stop_event.clear()
            self._ip_snapshot = self._get_current_ips()
            _logger.info("NetworkMonitor: initial IP snapshot: %s", sorted(self._ip_snapshot))

            self._thread = threading.Thread(
                target=self._run_loop,
                name="network_monitor",
                daemon=True,
            )
            thread = self._thread

        thread.start()
        _logger.info("NetworkMonitor: started")

    def stop(self, *, timeout_seconds: float = 3.0) -> None:
        """Stop monitoring network changes."""
        with self._lock:
            thread = self._thread
            self._thread = None
            self._stop_event.set()

        if thread is not None:
            thread.join(timeout=timeout_seconds)
            _logger.info("NetworkMonitor: stopped")

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _get_current_ips() -> set[str]:
        """Return current LAN IPv4 addresses as a set."""
        try:
            from dt_image_search.instant_sharing.lan_discovery import get_lan_ip_addresses  # type: ignore[import-untyped]

            return set(get_lan_ip_addresses())
        except Exception:
            _logger.exception("NetworkMonitor: failed to get current IPs")
            return set()

    def _on_network_changed(self, store, changed_keys, info) -> None:
        """SystemConfiguration callback — fires on *any* network state change.

        We re-read the current IP set and compare against the snapshot.  If the
        set differs we update the snapshot and publish the event.
        """
        _logger.debug("NetworkMonitor: network change detected, keys=%s", changed_keys)
        new_ips = self._get_current_ips()

        with self._lock:
            old_ips = self._ip_snapshot

        if new_ips != old_ips:
            _logger.info(
                "NetworkMonitor: IPs changed  old=%s  new=%s",
                sorted(old_ips),
                sorted(new_ips),
            )
            with self._lock:
                self._ip_snapshot = new_ips

            from dt_image_search.tools.dts_event_bus import default_bus  # type: ignore[import-untyped,import-not-found]

            default_bus.publish("is.network.ip_changed", old_ips=old_ips, new_ips=new_ips)
        else:
            _logger.debug("NetworkMonitor: IPs unchanged, ignoring")

    # ------------------------------------------------------------------
    # CFRunLoop thread
    # ------------------------------------------------------------------

    def _run_loop(self) -> None:
        """Entry point for the monitor thread.

        Creates an SCDynamicStore, subscribes to IPv4 interface-change keys,
        attaches the source to the current thread's CFRunLoop, and runs the
        loop until ``_stop_event`` is set.
        """
        # The macOS framework symbols are imported conditionally at module
        # level and are only reachable when _HAS_NATIVE_MONITOR is True.
        # Suppress false-positive "possibly unbound" warnings.
        try:
            store = SCDynamicStoreCreate(  # type: ignore[possibly-undefined]
                None,
                "AuSearch.NetworkMonitor",
                self._on_network_changed,
                None,
            )

            # Subscribe to per-interface IPv4 state changes
            patterns = ["State:/Network/Interface/.*/IPv4"]
            SCDynamicStoreSetNotificationKeys(store, None, patterns)  # type: ignore[possibly-undefined]

            loop_source = SCDynamicStoreCreateRunLoopSource(None, store, 0)  # type: ignore[possibly-undefined]
            CFRunLoopAddSource(CFRunLoopGetCurrent(), loop_source, kCFRunLoopDefaultMode)  # type: ignore[possibly-undefined]

            _logger.info("NetworkMonitor: CFRunLoop started, waiting for network events")

            # Run the loop in short bursts so we can periodically check the
            # stop event.  A 1 s timeout is negligible overhead.
            while not self._stop_event.is_set():
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, False)  # type: ignore[possibly-undefined]

        except Exception:
            _logger.exception("NetworkMonitor: _run_loop failed")
        finally:
            _logger.info("NetworkMonitor: _run_loop exiting")


# Module-level singleton — the primary instance consumed by other modules.
default_monitor = NetworkMonitor()
