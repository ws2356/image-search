"""
Loading widget with blue ring spinner and descriptive text.
Redesigned to match the new design specification.
"""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Spacing,
    Typography,
)
from dt_image_search.instant_sharing.mobile_to_pc.components.progress import SpinnerWidget
from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
    _TERMINAL_PHASES,
    _phase_message,
)
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    _make_font,
    apply_button_style,
)


class LoadingWidget(QWidget):
    """Widget that shows connection/negotiation/transfer progress.

    Displays a blue ring spinner, "Connecting..." heading, and
    descriptive subtitle text. Cancel button is ghost style (no border).
    """
    cancelled = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._state = MiniWindowState()
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(Spacing.SECTION_GAP)

        # Blue ring spinner (56x56)
        self._spinner = SpinnerWidget(size=56)
        spinner_layout = QHBoxLayout()
        spinner_layout.addStretch()
        spinner_layout.addWidget(self._spinner)
        spinner_layout.addStretch()
        layout.addLayout(spinner_layout)

        # Heading
        self._heading_label = QLabel("Connecting...")
        self._heading_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        heading_font = _make_font(Typography.HEADING_SIZE, weight=QFont.Weight.Bold)
        self._heading_label.setFont(heading_font)
        self._heading_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")
        layout.addWidget(self._heading_label)

        # Subtitle
        self._subtitle_label = QLabel()
        self._subtitle_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._subtitle_label.setWordWrap(True)
        subtitle_font = _make_font(Typography.SUBTITLE_SIZE, weight=QFont.Weight.Normal)
        self._subtitle_label.setFont(subtitle_font)
        self._subtitle_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._subtitle_label)

        layout.addStretch()

        # Cancel button (ghost style — no border)
        self._cancel_button = QPushButton("Cancel")
        self._cancel_button.clicked.connect(self.cancelled.emit)
        apply_button_style(self._cancel_button, "ghost")
        layout.addWidget(self._cancel_button)

    def set_state(self, state: MiniWindowState) -> None:
        self._state = state
        phase = state.phase

        # Update heading based on phase
        if phase == MiniWindowPhase.TRANSFERRING:
            self._heading_label.setText("Receiving...")
        elif phase == MiniWindowPhase.DELIVERING:
            self._heading_label.setText("Saving...")
        else:
            self._heading_label.setText("Connecting...")

        # Update subtitle
        message = state.error_message or _phase_message(
            phase,
            state.device_name,
            state.payload_label,
            state.pin_code,
            state.image_count,
            state.received_count,
        )
        self._subtitle_label.setText(message)

        # Show/hide cancel button
        is_terminal = phase in _TERMINAL_PHASES
        self._cancel_button.setVisible(
            phase in (
                MiniWindowPhase.CONNECTING,
                MiniWindowPhase.NEGOTIATING,
                MiniWindowPhase.DISPLAYING_PIN,
                MiniWindowPhase.TRANSFERRING,
            )
            and not is_terminal
        )
