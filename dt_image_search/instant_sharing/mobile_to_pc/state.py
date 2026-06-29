from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class MiniWindowPhase(str, Enum):
    CONNECTING = "connecting"
    NEGOTIATING = "negotiating"
    DISPLAYING_PIN = "displaying_pin"
    TRANSFERRING = "transferring"
    DELIVERING = "delivering"
    SUCCESS = "success"
    FAILED = "failed"
    TIMED_OUT = "timed_out"
    ABORTED = "aborted"
    BUSY = "busy"


_TERMINAL_PHASES = frozenset({
    MiniWindowPhase.SUCCESS,
    MiniWindowPhase.FAILED,
    MiniWindowPhase.TIMED_OUT,
    MiniWindowPhase.ABORTED,
    MiniWindowPhase.BUSY,
})


@dataclass
class MiniWindowState:
    phase: MiniWindowPhase = MiniWindowPhase.CONNECTING
    device_name: str = ""
    payload_label: str = "shared item"
    error_message: str = ""
    download_progress: float = 0.0
    pin_code: str = ""
    text_content: str = ""
    file_path: str = ""
    image_count: int = 0
    received_count: int = 0


def _phase_message(phase: MiniWindowPhase, device_name: str, payload_label: str, pin_code: str = "", image_count: int = 0, received_count: int = 0) -> str:
    name = device_name or "your phone"
    if phase == MiniWindowPhase.CONNECTING:
        return f"Establishing secure connection to {name}"
    if phase == MiniWindowPhase.NEGOTIATING:
        return f"Verifying trust with {name}..."
    if phase == MiniWindowPhase.DISPLAYING_PIN:
        return f"Verify this PIN matches the one on your iPhone:\n{pin_code}"
    if phase == MiniWindowPhase.TRANSFERRING:
        if image_count > 1:
            return f"Receiving image {received_count} of {image_count}..."
        return f"Receiving {payload_label} from iPhone..."
    if phase == MiniWindowPhase.DELIVERING:
        return f"Saving {payload_label}..."
    if phase == MiniWindowPhase.SUCCESS:
        return f"{payload_label.capitalize()} received successfully."
    if phase == MiniWindowPhase.FAILED:
        return "Handshake failed. Ensure both devices are on the same Wi-Fi network."
    if phase == MiniWindowPhase.TIMED_OUT:
        return "Transfer timed out."
    if phase == MiniWindowPhase.ABORTED:
        return "Transfer was canceled."
    if phase == MiniWindowPhase.BUSY:
        return "Another share is already in progress.\nPlease wait or cancel the current session on iPhone."
    return ""


def _phase_icon(phase: MiniWindowPhase) -> str:
    if phase == MiniWindowPhase.CONNECTING:
        return "📡"
    if phase == MiniWindowPhase.NEGOTIATING:
        return "🔐"
    if phase == MiniWindowPhase.DISPLAYING_PIN:
        return "🔑"
    if phase == MiniWindowPhase.TRANSFERRING:
        return "⬇️"
    if phase == MiniWindowPhase.DELIVERING:
        return "💾"
    if phase == MiniWindowPhase.SUCCESS:
        return "✅"
    if phase == MiniWindowPhase.FAILED:
        return "❌"
    if phase == MiniWindowPhase.TIMED_OUT:
        return "⏰"
    if phase == MiniWindowPhase.ABORTED:
        return "🛑"
    if phase == MiniWindowPhase.BUSY:
        return "⏳"
    return "📡"


def _payload_label(payload_class: str) -> str:
    if payload_class == "text":
        return "shared text"
    if payload_class == "image":
        return "shared image"
    return "shared item"
