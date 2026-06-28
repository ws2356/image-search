from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
    _phase_icon,
)


class PinCodeWidget(QWidget):
    """Widget that displays the PIN code for phone-based verification.

    Shown during the DISPLAYING_PIN phase. Shows the 6-digit PIN
    prominently along with a verification message and cancel button.
    """
    cancelled = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(16)

        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignCenter)
        self._icon_label.setFixedHeight(48)
        layout.addWidget(self._icon_label)

        self._message_label = QLabel()
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setMinimumHeight(48)
        layout.addWidget(self._message_label)

        self._pin_label = QLabel()
        self._pin_label.setAlignment(Qt.AlignCenter)
        self._pin_label.setWordWrap(False)
        pin_font = self._pin_label.font()
        pin_font.setPointSize(36)
        pin_font.setBold(True)
        self._pin_label.setFont(pin_font)
        self._pin_label.setStyleSheet("letter-spacing: 8px;")
        layout.addWidget(self._pin_label)

        layout.addStretch()

        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self._cancel_button = QPushButton("Cancel")
        self._cancel_button.clicked.connect(self.cancelled.emit)
        button_layout.addWidget(self._cancel_button)

        layout.addLayout(button_layout)

    def set_state(self, state: MiniWindowState) -> None:
        self._icon_label.setText(_phase_icon(state.phase))
        message = state.error_message or (
            f"Verify this PIN matches the one on your "
            f"{state.device_name or 'iPhone'}:"
        )
        self._message_label.setText(message)
        self._pin_label.setText(state.pin_code)
