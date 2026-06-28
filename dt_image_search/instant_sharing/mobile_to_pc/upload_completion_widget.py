"""
Upload completion widget with success/error icons, file info cards, and action buttons.
Redesigned to match the new design specification.
"""

from __future__ import annotations

import os

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
from dt_image_search.instant_sharing.mobile_to_pc.components.cards import (
    FileInfoCard,
    TextPreviewCard,
)
from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
    _phase_message,
)


def _get_file_type(file_path: str) -> str:
    """Extract file type extension from path."""
    _, ext = os.path.splitext(file_path)
    return ext.lstrip(".").upper() if ext else "FILE"


def _get_file_size_str(file_path: str) -> str:
    """Get human-readable file size."""
    try:
        size = os.path.getsize(file_path)
        if size < 1024:
            return f"{size} B"
        elif size < 1024 * 1024:
            return f"{size / 1024:.1f} KB"
        else:
            return f"{size / (1024 * 1024):.1f} MB"
    except OSError:
        return ""


class UploadCompletionWidget(QWidget):
    """Widget that shows the terminal result of a mobile-to-pc transfer.

    Shows success icon + file info card, or error icon + retry button.
    """
    dismissed = Signal()
    copy_requested = Signal()
    open_requested = Signal()
    retry_requested = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._state = MiniWindowState()
        self._setup_ui()

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Top spacer to push content toward vertical center
        layout.addStretch(1)

        # Status icon (success/error)
        self._icon_label = QLabel()
        self._icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._icon_label.setFixedSize(56, 56)
        layout.addWidget(self._icon_label, alignment=Qt.AlignmentFlag.AlignCenter)

        layout.addSpacing(12)

        # Heading
        self._heading_label = QLabel()
        self._heading_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        heading_font = QFont()
        heading_font.setPointSize(Typography.HEADING_SIZE)
        heading_font.setBold(True)
        self._heading_label.setFont(heading_font)
        self._heading_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")
        layout.addWidget(self._heading_label)

        layout.addSpacing(4)

        # Subtitle
        self._subtitle_label = QLabel()
        self._subtitle_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._subtitle_label.setWordWrap(True)
        subtitle_font = QFont()
        subtitle_font.setPointSize(Typography.SUBTITLE_SIZE)
        self._subtitle_label.setFont(subtitle_font)
        self._subtitle_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._subtitle_label)

        layout.addSpacing(16)

        # File info card (for file completion)
        self._file_card = FileInfoCard()
        self._file_card.hide()
        layout.addWidget(self._file_card)

        # Text preview card (for text completion)
        self._text_card = TextPreviewCard()
        self._text_card.hide()
        layout.addWidget(self._text_card)

        # Bottom spacer to push content toward vertical center
        layout.addStretch(1)

        # Button row
        self._button_layout = QHBoxLayout()
        self._button_layout.setSpacing(Spacing.ITEM_GAP)

        self._dismiss_button = QPushButton("Close")
        self._dismiss_button.clicked.connect(self.dismissed.emit)
        self._dismiss_button.setStyleSheet(f"""
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
        self._button_layout.addWidget(self._dismiss_button)

        self._copy_button = QPushButton("Copy Text")
        self._copy_button.clicked.connect(self.copy_requested.emit)
        self._copy_button.setStyleSheet(f"""
            QPushButton {{
                background-color: {Colors.PRIMARY_BLUE};
                color: white;
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}pt;
                font-weight: bold;
                min-height: {Spacing.BUTTON_HEIGHT - 24}px;
            }}
            QPushButton:hover {{
                background-color: #2563EB;
            }}
        """)
        self._copy_button.hide()
        self._button_layout.addWidget(self._copy_button)

        self._open_button = QPushButton("Show in Finder")
        self._open_button.clicked.connect(self.open_requested.emit)
        self._open_button.setStyleSheet(f"""
            QPushButton {{
                background-color: {Colors.PRIMARY_DARK};
                color: white;
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}pt;
                font-weight: bold;
                min-height: {Spacing.BUTTON_HEIGHT - 24}px;
            }}
            QPushButton:hover {{
                background-color: #243656;
            }}
        """)
        self._open_button.hide()
        self._button_layout.addWidget(self._open_button)

        self._retry_button = QPushButton("Retry")
        self._retry_button.clicked.connect(self.retry_requested.emit)
        self._retry_button.setStyleSheet(f"""
            QPushButton {{
                background-color: {Colors.PRIMARY_DARK};
                color: white;
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}pt;
                font-weight: bold;
                min-height: {Spacing.BUTTON_HEIGHT - 24}px;
            }}
            QPushButton:hover {{
                background-color: #243656;
            }}
        """)
        self._retry_button.hide()
        self._button_layout.addWidget(self._retry_button)

        layout.addLayout(self._button_layout)

    def set_state(self, state: MiniWindowState) -> None:
        self._state = state
        phase = state.phase

        # Set icon and heading based on phase
        if phase == MiniWindowPhase.SUCCESS:
            self._icon_label.setText("✓")
            self._icon_label.setStyleSheet(f"""
                font-size: 28pt;
                color: white;
                background-color: {Colors.SUCCESS};
                border-radius: 28px;
                min-width: 56px;
                min-height: 56px;
                max-width: 56px;
                max-height: 56px;
                padding: 0px;
            """)
            has_text = bool(state.text_content)
            has_file = bool(state.file_path)
            if has_file:
                self._heading_label.setText("File Received")
                self._subtitle_label.setText("Saved to your Downloads folder")
            elif has_text:
                self._heading_label.setText("Text Received")
                self._subtitle_label.setText("Ready to paste anywhere on your Mac.")
            else:
                self._heading_label.setText("Sent!")
                self._subtitle_label.setText(state.payload_label.capitalize() + " delivered successfully.")
        else:
            # Error state
            self._icon_label.setText("!")
            self._icon_label.setStyleSheet(f"""
                font-size: 28pt;
                color: white;
                background-color: {Colors.ERROR};
                border-radius: 28px;
                min-width: 56px;
                min-height: 56px;
                max-width: 56px;
                max-height: 56px;
                padding: 0px;
            """)
            self._heading_label.setText("Connection Lost")
            error_msg = state.error_message or _phase_message(
                phase, state.device_name, state.payload_label,
                state.pin_code, state.image_count, state.received_count,
            )
            self._subtitle_label.setText(error_msg)

        # Show/hide file card
        if phase == MiniWindowPhase.SUCCESS and state.file_path:
            file_name = os.path.basename(state.file_path)
            file_type = _get_file_type(state.file_path)
            file_size = _get_file_size_str(state.file_path)
            file_dir = os.path.dirname(state.file_path)
            self._file_card.set_file_info(file_name, file_size, file_dir, file_type)
            self._file_card.show()
        else:
            self._file_card.hide()

        # Show/hide text card
        if phase == MiniWindowPhase.SUCCESS and state.text_content:
            self._text_card.set_text(state.text_content)
            self._text_card.show()
        else:
            self._text_card.hide()

        # Show/hide buttons
        self._dismiss_button.show()
        self._copy_button.setVisible(phase == MiniWindowPhase.SUCCESS and bool(state.text_content))
        self._open_button.setVisible(phase == MiniWindowPhase.SUCCESS and bool(state.file_path))
        self._retry_button.setVisible(phase not in (MiniWindowPhase.SUCCESS, MiniWindowPhase.ABORTED))
