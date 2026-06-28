"""
Reusable card components for the instant-share PC mini-window.
Provides styled containers with background, border, and padding.
"""

from PySide6.QtCore import Qt
from PySide6.QtGui import QFontMetrics
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout, QWidget

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Spacing,
    Typography,
)
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    apply_body_label,
    apply_caption_label,
    apply_pin_digit_label,
)


class CardContainer(QFrame):
    """Styled card container with background and border."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setStyleSheet(f"""
            QFrame {{
                background-color: {Colors.SURFACE};
                border: 1px solid {Colors.BORDER};
                border-radius: {Spacing.CARD_RADIUS}px;
            }}
        """)
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(
            Spacing.CARD_PADDING, Spacing.CARD_PADDING,
            Spacing.CARD_PADDING, Spacing.CARD_PADDING,
        )
        self._layout.setSpacing(Spacing.ITEM_GAP)

    @property
    def card_layout(self) -> QVBoxLayout:
        return self._layout


class FileInfoCard(CardContainer):
    """File info card showing type badge, name, size, and path."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)

        row = QHBoxLayout()
        row.setSpacing(Spacing.ITEM_GAP)

        # File type badge
        self._type_badge = QLabel()
        self._type_badge.setAlignment(Qt.AlignCenter)
        self._type_badge.setFixedSize(40, 40)
        self._type_badge.setStyleSheet(f"""
            background-color: {Colors.PRIMARY_BLUE};
            color: white;
            border-radius: 8px;
            font-size: 11pt;
            font-weight: bold;
        """)
        row.addWidget(self._type_badge)

        # File info
        info_layout = QVBoxLayout()
        info_layout.setSpacing(2)

        self._name_label = QLabel()
        apply_body_label(self._name_label)
        self._name_label.setWordWrap(False)
        self._name_label.setMaximumWidth(220)
        self._name_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; font-weight: bold; background: transparent;")
        info_layout.addWidget(self._name_label)

        self._meta_label = QLabel()
        apply_caption_label(self._meta_label)
        info_layout.addWidget(self._meta_label)

        row.addLayout(info_layout, 1)

        self.card_layout.addLayout(row)

    def set_file_info(self, name: str, size: str, path: str, file_type: str = "") -> None:
        """Update the file info display."""
        self._type_badge.setText(file_type.upper()[:4] if file_type else "FILE")
        # Elide long filenames to prevent overflow
        fm = QFontMetrics(self._name_label.font())
        max_w = self._name_label.maximumWidth()
        if fm.horizontalAdvance(name) > max_w:
            name = fm.elidedText(name, Qt.ElideRight, max_w)
        self._name_label.setText(name)
        self._meta_label.setText(f"{size} · {path}")


class PINCard(CardContainer):
    """PIN display card with large digits."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._layout.setAlignment(Qt.AlignCenter)

        self._pin_label = QLabel()
        self._pin_label.setAlignment(Qt.AlignCenter)
        apply_pin_digit_label(self._pin_label)
        self._layout.addWidget(self._pin_label)

    def set_pin(self, pin: str) -> None:
        """Display the PIN with spacing between digits."""
        spaced = " ".join(pin)
        self._pin_label.setText(spaced)


class TextPreviewCard(CardContainer):
    """Text preview card with monospace font."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)

        self._text_label = QLabel()
        self._text_label.setWordWrap(True)
        self._text_label.setStyleSheet(f"""
            color: {Colors.TEXT_PRIMARY};
            font-family: "Menlo", "Courier New", monospace;
            font-size: {Typography.CAPTION_SIZE}pt;
            background: transparent;
        """)
        self._layout.addWidget(self._text_label)

    def set_text(self, text: str, max_chars: int = 200) -> None:
        """Display truncated text preview."""
        display = text[:max_chars]
        if len(text) > max_chars:
            display += "..."
        self._text_label.setText(display)
