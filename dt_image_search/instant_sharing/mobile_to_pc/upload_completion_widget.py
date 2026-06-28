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
    _phase_icon,
    _phase_message,
)


class UploadCompletionWidget(QWidget):
    """Widget that shows the terminal result of a mobile-to-pc transfer.

    Active during SUCCESS, FAILED, TIMED_OUT, ABORTED, and BUSY phases.
    Displays the result icon, message, optional error text, progress
    (100% for success / hidden for errors), and action buttons.
    """
    dismissed = Signal()
    copy_requested = Signal()
    open_requested = Signal()

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

        self._message_label = QLabel()
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setMinimumHeight(48)
        layout.addWidget(self._message_label)

        self._error_label = QLabel()
        self._error_label.setAlignment(Qt.AlignCenter)
        self._error_label.setWordWrap(True)
        self._error_label.setStyleSheet("color: #D70015;")
        self._error_label.hide()
        layout.addWidget(self._error_label)

        self._progress_bar = QProgressBar()
        self._progress_bar.setRange(0, 100)
        self._progress_bar.setValue(0)
        self._progress_bar.setTextVisible(False)
        self._progress_bar.setFixedHeight(6)
        layout.addWidget(self._progress_bar)

        layout.addStretch()

        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self._dismiss_button = QPushButton("Close")
        self._dismiss_button.clicked.connect(self.dismissed.emit)
        button_layout.addWidget(self._dismiss_button)

        self._copy_button = QPushButton("Copy to Clipboard")
        self._copy_button.clicked.connect(self.copy_requested.emit)
        self._copy_button.setVisible(False)
        button_layout.addWidget(self._copy_button)

        self._open_button = QPushButton("Show in Finder")
        self._open_button.clicked.connect(self.open_requested.emit)
        self._open_button.setVisible(False)
        button_layout.addWidget(self._open_button)

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

        if phase in (MiniWindowPhase.FAILED, MiniWindowPhase.TIMED_OUT, MiniWindowPhase.ABORTED):
            self._error_label.setText(message)
            self._error_label.show()
        else:
            self._error_label.hide()

        if phase == MiniWindowPhase.SUCCESS:
            self._progress_bar.setVisible(True)
            self._progress_bar.setRange(0, 100)
            self._progress_bar.setValue(100)
        else:
            self._progress_bar.setVisible(False)

        self._dismiss_button.setVisible(True)

        if phase == MiniWindowPhase.SUCCESS:
            has_text = bool(state.text_content)
            has_file = bool(state.file_path)
            self._copy_button.setVisible(has_text)
            self._open_button.setVisible(has_file)
        else:
            self._copy_button.setVisible(False)
            self._open_button.setVisible(False)
