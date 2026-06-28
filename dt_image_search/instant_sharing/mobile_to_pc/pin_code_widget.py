"""
PIN code display widget with lock icon, styled PIN card, and progress indicator.
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
    Icons,
    Spacing,
    Typography,
)
from dt_image_search.instant_sharing.mobile_to_pc.components.cards import PINCard
from dt_image_search.instant_sharing.mobile_to_pc.components.progress import StatusProgressBar
from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
)


class PinCodeWidget(QWidget):
    """Widget that displays the PIN code for phone-based verification.

    Shows lock icon in yellow/orange rounded square, styled PIN card,
    progress bar, and status text.
    """
    cancelled = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(Spacing.SECTION_GAP)

        # Lock icon in yellow/orange rounded square
        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._icon_label.setFixedSize(56, 56)
        self._icon_label.setStyleSheet(f"""
            font-size: 28pt;
            background-color: {Colors.WARNING_BG};
            border-radius: 12px;
            padding: 0px;
        """)
        layout.addWidget(self._icon_label, alignment=Qt.AlignmentFlag.AlignCenter)

        # Heading
        self._heading_label = QLabel("Verify Device")
        self._heading_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        heading_font = QFont()
        heading_font.setPointSize(Typography.HEADING_SIZE)
        heading_font.setBold(True)
        self._heading_label.setFont(heading_font)
        self._heading_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")
        layout.addWidget(self._heading_label)

        # Subtitle
        self._subtitle_label = QLabel()
        self._subtitle_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._subtitle_label.setWordWrap(True)
        subtitle_font = QFont()
        subtitle_font.setPointSize(Typography.SUBTITLE_SIZE)
        self._subtitle_label.setFont(subtitle_font)
        self._subtitle_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._subtitle_label)

        # PIN card
        self._pin_card = PINCard()
        layout.addWidget(self._pin_card)

        # Progress bar
        self._progress_bar = StatusProgressBar()
        self._progress_bar.setRange(0, 0)  # indeterminate
        layout.addWidget(self._progress_bar)

        # Status text
        self._status_label = QLabel("Waiting for PIN entry on iPhone...")
        self._status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        status_font = QFont()
        status_font.setPointSize(Typography.CAPTION_SIZE)
        self._status_label.setFont(status_font)
        self._status_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._status_label)

        layout.addStretch()

        # Cancel button (ghost style)
        self._cancel_button = QPushButton("Cancel Request")
        self._cancel_button.clicked.connect(self.cancelled.emit)
        self._cancel_button.setStyleSheet(f"""
            QPushButton {{
                background-color: {Colors.GHOST_BG};
                color: {Colors.GHOST_TEXT};
                border: 1px solid {Colors.GHOST_BORDER};
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}pt;
                font-weight: bold;
                min-height: {Spacing.BUTTON_HEIGHT - 24}px;
            }}
            QPushButton:hover {{
                background-color: {Colors.DISABLED_BG};
            }}
        """)
        layout.addWidget(self._cancel_button)

    def set_state(self, state: MiniWindowState) -> None:
        self._icon_label.setText(Icons.LOCK)
        message = state.error_message or (
            f"Verify this PIN matches the one on your "
            f"{state.device_name or 'iPhone'}:"
        )
        self._subtitle_label.setText(message)
        self._pin_card.set_pin(state.pin_code)
