"""
PIN code display widget with lock icon, styled PIN card, and progress indicator.
Redesigned to match the new design specification with amber lock icon,
yellow status dot, and ghost-style cancel button.
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
    QSizePolicy,
)
from PySide6.QtSvgWidgets import QSvgWidget

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
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    _make_font,
    apply_button_style,
)


class PinCodeWidget(QWidget):
    """Widget that displays the PIN code for phone-based verification.

    Shows amber lock icon in amber-50 rounded square, styled PIN card,
    progress bar, and status text with yellow dot indicator.
    """
    cancelled = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(Spacing.SECTION_GAP)

        # Lock icon in amber-50 rounded square
        self._icon_label = QSvgWidget()
        self._icon_label.setStyleSheet("background: transparent; border: none;")
        self._icon_label.load(bytearray('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/></svg>', "utf-8"))
        self._icon_container = QWidget()
        self._icon_container.setFixedSize(44, 44)
        self._icon_container.setStyleSheet(f"background-color: {Colors.WARNING_BG}; border: 1px solid #fef3c7; border-radius: 16px;")
        icon_layout = QVBoxLayout(self._icon_container)
        icon_layout.setContentsMargins(10, 10, 10, 10)
        icon_layout.addWidget(self._icon_label)
        layout.addWidget(self._icon_container, alignment=Qt.AlignmentFlag.AlignCenter)

        # Heading
        self._heading_label = QLabel("Verify Device")
        self._heading_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        heading_font = _make_font(Typography.HEADING_SIZE, weight=QFont.Weight.Bold)
        self._heading_label.setFont(heading_font)
        self._heading_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")
        layout.addWidget(self._heading_label)

        # Subtitle
        self._subtitle_label = QLabel()
        self._subtitle_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._subtitle_label.setWordWrap(True)
        self._subtitle_label.setMaximumWidth(210)
        subtitle_font = _make_font(Typography.SUBTITLE_SIZE, weight=QFont.Weight.Normal)
        self._subtitle_label.setFont(subtitle_font)
        self._subtitle_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._subtitle_label)

        # PIN card
        self._pin_card = PINCard()
        self._pin_card.setMaximumWidth(270)
        layout.addWidget(self._pin_card, alignment=Qt.AlignmentFlag.AlignCenter)

        # Progress bar (4px, indeterminate)
        self._progress_bar = StatusProgressBar()
        self._progress_bar.setRange(0, 0)  # indeterminate
        # Status row: yellow dot + label
        status_layout = QHBoxLayout()
        status_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        status_layout.setSpacing(8)

        self._status_dot = QLabel()
        self._status_dot.setFixedSize(8, 8)
        self._status_dot.setStyleSheet(f"""
            background-color: {Colors.WARNING_LIGHT};
            border-radius: 4px;
            min-width: 8px;
            min-height: 8px;
            max-width: 8px;
            max-height: 8px;
        """)
        status_layout.addWidget(self._status_dot)

        self._status_label = QLabel("Waiting for PIN entry on iPhone\u2026")
        self._status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        status_font = _make_font(Typography.CAPTION_SIZE, weight=QFont.Weight.Normal)
        self._status_label.setFont(status_font)
        self._status_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        status_layout.addWidget(self._status_label)

        layout.addLayout(status_layout)

        # Progress bar (4px, indeterminate)
        self._progress_bar = StatusProgressBar()
        self._progress_bar.setRange(0, 0)  # indeterminate
        layout.addWidget(self._progress_bar)
        status_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        status_layout.setSpacing(8)

        self._status_dot = QLabel()
        self._status_dot.setFixedSize(8, 8)
        self._status_dot.setStyleSheet(f"""
            background-color: {Colors.WARNING_LIGHT};
            border-radius: 4px;
            min-width: 8px;
            min-height: 8px;
            max-width: 8px;
            max-height: 8px;
        """)
        layout.addStretch()

        # Cancel button (ghost style — no border)
        self._cancel_button = QPushButton("Cancel Request")
        self._cancel_button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self._cancel_button.clicked.connect(self.cancelled.emit)
        apply_button_style(self._cancel_button, "ghost")
        layout.addWidget(self._cancel_button)

    def set_state(self, state: MiniWindowState) -> None:
        pass
        message = state.error_message or (
            f"Enter this PIN on your {state.device_name or 'iPhone'} "
            f"to authorize the secure pairing."
        )
        self._subtitle_label.setText(message)
        self._pin_card.set_pin(state.pin_code)
