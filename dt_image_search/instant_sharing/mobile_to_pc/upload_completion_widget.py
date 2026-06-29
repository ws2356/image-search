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
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)
from PySide6.QtSvgWidgets import QSvgWidget

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
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    _make_font,
    apply_button_style,
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


from PySide6.QtGui import QIcon, QPixmap
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtCore import QSize

class UploadCompletionWidget(QWidget):
    def _create_svg_icon(self, svg_string: str) -> QIcon:
        renderer = QSvgRenderer(bytearray(svg_string, "utf-8"))
        pixmap = QPixmap(14, 14)
        pixmap.fill(Qt.GlobalColor.transparent)
        import PySide6.QtGui as QtGui
        painter = QtGui.QPainter(pixmap)
        renderer.render(painter)
        painter.end()
        return QIcon(pixmap)

    """Widget that shows the terminal result of a mobile-to-pc transfer.

    Shows success icon (green circle) + file info card, or error icon (red circle) + retry button.
    Action buttons follow design spec: ghost (Close), dark (Show in Finder/Retry), blue (Copy Text).
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
        self._icon_container = QWidget()
        self._icon_container.setFixedSize(56, 56)
        self._icon_container.setStyleSheet(f"background-color: {Colors.SUCCESS_BG}; border-radius: 28px;")
        self._icon_layout = QVBoxLayout(self._icon_container)
        self._icon_layout.setContentsMargins(14, 14, 14, 14)
        self._icon_svg = QSvgWidget()
        self._icon_svg.setStyleSheet("background: transparent; border: none;")
        self._icon_layout.addWidget(self._icon_svg)
        
        self._icon_wrapper = QWidget()
        self._icon_wrapper.setFixedSize(72, 72)
        self._icon_wrapper.setStyleSheet(f"border: 1px solid rgba(16, 185, 129, 0.6); border-radius: 36px;")
        wrapper_layout = QVBoxLayout(self._icon_wrapper)
        wrapper_layout.setContentsMargins(7, 7, 7, 7)
        wrapper_layout.addWidget(self._icon_container)
        
        layout.addWidget(self._icon_wrapper, alignment=Qt.AlignmentFlag.AlignCenter)

        layout.addSpacing(12)

        # Heading
        self._heading_label = QLabel()
        self._heading_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        heading_font = _make_font(Typography.HEADING_SIZE, weight=QFont.Weight.Bold)
        self._heading_label.setFont(heading_font)
        self._heading_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")
        layout.addWidget(self._heading_label)

        layout.addSpacing(4)

        # Subtitle
        self._subtitle_label = QLabel()
        self._subtitle_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._subtitle_label.setWordWrap(True)
        subtitle_font = _make_font(Typography.SUBTITLE_SIZE, weight=QFont.Weight.Normal)
        self._subtitle_label.setFont(subtitle_font)
        self._subtitle_label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")
        layout.addWidget(self._subtitle_label)

        layout.addSpacing(16)

        # File info card (for file completion)
        self._file_card = FileInfoCard()
        self._file_card.setMaximumWidth(270)
        self._file_card.hide()
        layout.addWidget(self._file_card, alignment=Qt.AlignmentFlag.AlignCenter)

        # Text preview card (for text completion)
        self._text_card = TextPreviewCard()
        self._text_card.setMaximumWidth(280)
        self._text_card.hide()
        layout.addWidget(self._text_card, alignment=Qt.AlignmentFlag.AlignCenter)

        # Bottom spacer to push content toward vertical center
        layout.addStretch(1)

        # Button row
        self._button_layout = QHBoxLayout()
        
        self._button_layout.setSpacing(10)

        # Spacer labels for centering the Retry button in error state
        self._button_left_spacer = QLabel()
        self._button_left_spacer.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        self._button_left_spacer.hide()
        self._button_layout.addWidget(self._button_left_spacer)

        # Close button — ghost style
        self._dismiss_button = QPushButton("Close")
        self._dismiss_button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self._dismiss_button.clicked.connect(self.dismissed.emit)
        apply_button_style(self._dismiss_button, "ghost")
        self._button_layout.addWidget(self._dismiss_button)

        # Copy Text button — primary blue
        self._copy_button = QPushButton("Copy Text")
        self._copy_button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self._copy_button.setIcon(self._create_svg_icon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>'))
        self._copy_button.clicked.connect(self.copy_requested.emit)
        apply_button_style(self._copy_button, "primary_blue")
        self._copy_button.hide()
        self._button_layout.addWidget(self._copy_button)

        # Show in Finder button — primary dark
        self._open_button = QPushButton("Show in Finder")
        self._open_button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self._open_button.setIcon(self._create_svg_icon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>'))
        self._open_button.clicked.connect(self.open_requested.emit)
        apply_button_style(self._open_button, "primary_dark")
        self._open_button.hide()
        self._button_layout.addWidget(self._open_button)

        # Retry button — primary dark
        self._retry_button = QPushButton("Retry")
        self._retry_button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self._retry_button.setIcon(self._create_svg_icon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"></polyline><polyline points="1 20 1 14 7 14"></polyline><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path></svg>'))
        self._retry_button.clicked.connect(self.retry_requested.emit)
        apply_button_style(self._retry_button, "primary_dark")
        self._retry_button.hide()
        self._button_layout.addWidget(self._retry_button)

        # Right spacer label for centering
        self._button_right_spacer = QLabel()
        self._button_right_spacer.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        self._button_right_spacer.hide()
        self._button_layout.addWidget(self._button_right_spacer)

        layout.addLayout(self._button_layout)

    def set_state(self, state: MiniWindowState) -> None:
        self._state = state
        phase = state.phase

        # Set icon and heading based on phase
        if phase == MiniWindowPhase.SUCCESS:
            self._icon_svg.load(bytearray('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#059669" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>', "utf-8"))
            self._icon_container.setStyleSheet(f"background-color: {Colors.SUCCESS_BG}; border-radius: 28px;")
            self._icon_wrapper.setStyleSheet(f"border: 1px solid rgba(16, 185, 129, 0.6); border-radius: 36px;")
            has_text = bool(state.text_content)
            has_file = bool(state.file_path)
            if has_file:
                self._heading_label.setText("File Received")
                self._subtitle_label.setText("Saved to your Downloads folder.")
            elif has_text:
                self._heading_label.setText("Text Received")
                self._subtitle_label.setText("Ready to paste anywhere on your Mac.")
            else:
                self._heading_label.setText("Sent!")
                self._subtitle_label.setText(state.payload_label.capitalize() + " delivered successfully.")
        else:
            # Error state
            self._icon_svg.load(bytearray('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg>', "utf-8"))
            self._icon_container.setStyleSheet(f"background-color: {Colors.ERROR_BG}; border-radius: 28px;")
            self._icon_wrapper.setStyleSheet("border: none;")
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
            if file_dir.startswith(os.path.expanduser("~")):
                file_dir = file_dir.replace(os.path.expanduser("~"), "~", 1)
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
        is_error = phase in (MiniWindowPhase.FAILED, MiniWindowPhase.TIMED_OUT, MiniWindowPhase.BUSY)
        if is_error:
            # Error state: single centered Retry button, no Close button
            self._dismiss_button.hide()
            self._copy_button.hide()
            self._open_button.hide()
            self._retry_button.show()
            
            
        else:
            # Success or aborted state
            self._dismiss_button.show()
            self._copy_button.setVisible(phase == MiniWindowPhase.SUCCESS and bool(state.text_content))
            self._open_button.setVisible(phase == MiniWindowPhase.SUCCESS and bool(state.file_path))
            self._retry_button.hide()
            self._button_left_spacer.hide()
            self._button_right_spacer.hide()
