from __future__ import annotations

import sys
import threading

from PySide6.QtWidgets import QWidget

_ref_count = 0
_lock = threading.Lock()


def acquire_activation_policy() -> None:
    global _ref_count
    with _lock:
        _ref_count += 1
        if _ref_count == 1:
            _set_regular()


def release_activation_policy() -> None:
    global _ref_count
    with _lock:
        _ref_count -= 1
        if _ref_count <= 0:
            _ref_count = 0
            _set_accessory()


def _set_regular() -> None:
    if sys.platform != "darwin":
        return
    try:
        from AppKit import NSApplication, NSApplicationActivationPolicyRegular
        NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyRegular)
    except ImportError:
        pass


def _set_accessory() -> None:
    if sys.platform != "darwin":
        return
    try:
        from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
        NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    except ImportError:
        pass


def bring_to_front(window: QWidget) -> None:
    window.raise_()
    window.activateWindow()
