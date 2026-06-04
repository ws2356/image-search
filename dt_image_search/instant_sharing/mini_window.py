from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QFont, QIcon
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)


WINDOW_WIDTH = 360
WINDOW_HEIGHT = 520


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


def _phase_message(phase: MiniWindowPhase, device_name: str, payload_label: str, pin_code: str = "") -> str:
    name = device_name or "your Mac"
    if phase == MiniWindowPhase.CONNECTING:
        return f"Connecting to {name}..."
    if phase == MiniWindowPhase.NEGOTIATING:
        return f"Verifying trust with {name}..."
    if phase == MiniWindowPhase.DISPLAYING_PIN:
        return f"Verify this PIN matches the one on your iPhone:\n{pin_code}"
    if phase == MiniWindowPhase.TRANSFERRING:
        return f"Receiving {payload_label} from iPhone..."
    if phase == MiniWindowPhase.DELIVERING:
        return f"Saving {payload_label}..."
    if phase == MiniWindowPhase.SUCCESS:
        return f"{payload_label.capitalize()} received successfully."
    if phase == MiniWindowPhase.FAILED:
        return "Transfer failed."
    if phase == MiniWindowPhase.TIMED_OUT:
        return "Transfer timed out."
    if phase == MiniWindowPhase.ABORTED:
        return "Transfer was canceled."
    if phase == MiniWindowPhase.BUSY:
        return "Another share is already in progress.\nPlease wait or cancel the current session on iPhone."
    return ""


class InstantShareMiniWindow(QDialog):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._state = MiniWindowState()
        self._auto_close_timer: QTimer | None = None
        self._setup_ui()

    @staticmethod
    def build_phase(state_value: str) -> MiniWindowPhase:
        state_lower = state_value.lower()
        if state_lower in ("bootstrapped", "queued", "connecting"):
            return MiniWindowPhase.CONNECTING
        if state_lower == "negotiating":
            return MiniWindowPhase.NEGOTIATING
        if state_lower == "displaying_pin":
            return MiniWindowPhase.DISPLAYING_PIN
        if state_lower == "transferring":
            return MiniWindowPhase.TRANSFERRING
        if state_lower == "delivering":
            return MiniWindowPhase.DELIVERING
        if state_lower == "done":
            return MiniWindowPhase.SUCCESS
        if state_lower == "failed":
            return MiniWindowPhase.FAILED
        if state_lower == "timed_out":
            return MiniWindowPhase.TIMED_OUT
        if state_lower == "aborted":
            return MiniWindowPhase.ABORTED
        return MiniWindowPhase.CONNECTING

    def apply_session_event(
        self,
        *,
        state: str,
        device_name: str = "",
        payload_class: str = "",
        error_message: str = "",
    ) -> None:
        phase = self.build_phase(state)
        label = _payload_label(payload_class) if payload_class else self._state.payload_label
        device = device_name or self._state.device_name

        self._state = MiniWindowState(
            phase=phase,
            device_name=device,
            payload_label=label,
            error_message=error_message,
            download_progress=1.0 if phase == MiniWindowPhase.SUCCESS else 0.0,
            pin_code=self._state.pin_code,
        )
        self._refresh_ui()

        if phase in _TERMINAL_PHASES:
            self._schedule_auto_close()

    def show_pin(self, pin_code: str) -> None:
        self._state = MiniWindowState(
            phase=MiniWindowPhase.DISPLAYING_PIN,
            device_name=self._state.device_name,
            payload_label=self._state.payload_label,
            pin_code=pin_code,
        )
        self._refresh_ui()

    def _schedule_auto_close(self) -> None:
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
        delay = 4000 if self._state.phase == MiniWindowPhase.SUCCESS else 8000
        self._auto_close_timer = QTimer(self)
        self._auto_close_timer.setSingleShot(True)
        self._auto_close_timer.timeout.connect(self.close)
        self._auto_close_timer.start(delay)

    def _setup_ui(self) -> None:
        self.setWindowTitle("Instant Share")
        self.setFixedSize(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.setAttribute(Qt.WA_DeleteOnClose)

        app_icon = QApplication.windowIcon()
        if not app_icon.isNull():
            self.setWindowIcon(app_icon)

        self._main_layout = QVBoxLayout(self)
        self._main_layout.setContentsMargins(24, 24, 24, 24)
        self._main_layout.setSpacing(16)

        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignCenter)
        self._icon_label.setFixedHeight(48)
        self._main_layout.addWidget(self._icon_label)

        self._title_label = QLabel("Instant Share")
        self._title_label.setAlignment(Qt.AlignCenter)
        font = self._title_label.font()
        font.setPointSize(18)
        font.setBold(True)
        self._title_label.setFont(font)
        self._main_layout.addWidget(self._title_label)

        self._message_label = QLabel()
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setMinimumHeight(48)
        self._main_layout.addWidget(self._message_label)

        self._pin_label = QLabel()
        self._pin_label.setAlignment(Qt.AlignCenter)
        self._pin_label.setWordWrap(False)
        pin_font = self._pin_label.font()
        pin_font.setPointSize(36)
        pin_font.setBold(True)
        self._pin_label.setFont(pin_font)
        self._pin_label.setStyleSheet("letter-spacing: 8px;")
        self._pin_label.hide()
        self._main_layout.addWidget(self._pin_label)

        self._progress_bar = QProgressBar()
        self._progress_bar.setRange(0, 100)
        self._progress_bar.setValue(0)
        self._progress_bar.setTextVisible(False)
        self._progress_bar.setFixedHeight(6)
        self._main_layout.addWidget(self._progress_bar)

        self._error_label = QLabel()
        self._error_label.setAlignment(Qt.AlignCenter)
        self._error_label.setWordWrap(True)
        self._error_label.setStyleSheet("color: #D70015;")
        self._error_label.hide()
        self._main_layout.addWidget(self._error_label)

        self._main_layout.addStretch()

        self._button_layout = QHBoxLayout()
        self._button_layout.setSpacing(12)

        self._abort_button = QPushButton("Cancel")
        self._abort_button.clicked.connect(self._on_abort)
        self._abort_button.setVisible(False)
        self._button_layout.addWidget(self._abort_button)

        self._dismiss_button = QPushButton("Close")
        self._dismiss_button.clicked.connect(self.close)
        self._dismiss_button.setVisible(False)
        self._button_layout.addWidget(self._dismiss_button)

        self._main_layout.addLayout(self._button_layout)

        self._refresh_ui()

    def _on_abort(self) -> None:
        self._state.phase = MiniWindowPhase.ABORTED
        self._state.error_message = "Canceled by user."
        self._refresh_ui()
        self._schedule_auto_close()

    def _refresh_ui(self) -> None:
        phase = self._state.phase
        self._icon_label.setText(_phase_icon(phase))

        message = self._state.error_message or _phase_message(
            phase,
            self._state.device_name,
            self._state.payload_label,
            self._state.pin_code,
        )
        self._message_label.setText(message)

        if phase == MiniWindowPhase.DISPLAYING_PIN:
            self._pin_label.setText(self._state.pin_code)
            self._pin_label.show()
        else:
            self._pin_label.hide()

        if phase in (MiniWindowPhase.TRANSFERRING, MiniWindowPhase.DELIVERING):
            self._progress_bar.setVisible(True)
            if self._state.download_progress > 0:
                self._progress_bar.setValue(int(self._state.download_progress * 100))
            else:
                self._progress_bar.setRange(0, 0)
        elif phase == MiniWindowPhase.SUCCESS:
            self._progress_bar.setVisible(True)
            self._progress_bar.setRange(0, 100)
            self._progress_bar.setValue(100)
        elif phase in (MiniWindowPhase.FAILED, MiniWindowPhase.TIMED_OUT, MiniWindowPhase.ABORTED, MiniWindowPhase.BUSY):
            self._progress_bar.setVisible(False)
        else:
            self._progress_bar.setVisible(True)
            self._progress_bar.setRange(0, 0)

        is_terminal = phase in _TERMINAL_PHASES
        self._abort_button.setVisible(
            phase in (MiniWindowPhase.CONNECTING, MiniWindowPhase.NEGOTIATING, MiniWindowPhase.DISPLAYING_PIN, MiniWindowPhase.TRANSFERRING)
            and not is_terminal
        )
        self._dismiss_button.setVisible(is_terminal)

        if phase in (MiniWindowPhase.FAILED, MiniWindowPhase.TIMED_OUT, MiniWindowPhase.ABORTED):
            self._error_label.setText(message)
            self._error_label.show()
        else:
            self._error_label.hide()

    def closeEvent(self, event) -> None:
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
            self._auto_close_timer = None
        super().closeEvent(event)


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
