from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
    _TERMINAL_PHASES,
    _phase_icon,
    _phase_message,
)


class LoadingWidget(QWidget):
    """Widget that shows connection/negotiation/transfer progress.

    Active during CONNECTING, NEGOTIATING, TRANSFERRING, and
    DELIVERING phases.  Displays a phase-appropriate icon, message,
    progress bar (indeterminate or determinate), and a cancel button.
    """
    cancelled = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._state = MiniWindowState()
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(16)

        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignCenter)
        self._icon_label.setFixedHeight(48)
        layout.addWidget(self._icon_label)

        self._title_label = QLabel("Instant Share")
        self._title_label.setAlignment(Qt.AlignCenter)
        font = self._title_label.font()
        font.setPointSize(18)
        font.setBold(True)
        self._title_label.setFont(font)
        layout.addWidget(self._title_label)

        self._message_label = QLabel()
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setMinimumHeight(48)
        layout.addWidget(self._message_label)

        self._progress_bar = QProgressBar()
        self._progress_bar.setRange(0, 100)
        self._progress_bar.setValue(0)
        self._progress_bar.setTextVisible(False)
        self._progress_bar.setFixedHeight(6)
        layout.addWidget(self._progress_bar)

        layout.addStretch()

        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self._cancel_button = QPushButton("Cancel")
        self._cancel_button.clicked.connect(self.cancelled.emit)
        button_layout.addWidget(self._cancel_button)

        layout.addLayout(button_layout)

    def set_state(self, state: MiniWindowState) -> None:
        self._state = state
        phase = state.phase

        self._icon_label.setText(_phase_icon(phase))

        message = state.error_message or _phase_message(
            phase,
            state.device_name,
            state.payload_label,
            state.pin_code,
            state.image_count,
            state.received_count,
        )
        self._message_label.setText(message)

        if phase in (MiniWindowPhase.TRANSFERRING, MiniWindowPhase.DELIVERING):
            self._progress_bar.setVisible(True)
            if state.download_progress > 0:
                self._progress_bar.setRange(0, 100)
                self._progress_bar.setValue(int(state.download_progress * 100))
            else:
                self._progress_bar.setRange(0, 0)
        else:
            self._progress_bar.setVisible(True)
            self._progress_bar.setRange(0, 0)

        is_terminal = phase in _TERMINAL_PHASES
        self._cancel_button.setVisible(
            phase
            in (
                MiniWindowPhase.CONNECTING,
                MiniWindowPhase.NEGOTIATING,
                MiniWindowPhase.DISPLAYING_PIN,
                MiniWindowPhase.TRANSFERRING,
            )
            and not is_terminal
        )
