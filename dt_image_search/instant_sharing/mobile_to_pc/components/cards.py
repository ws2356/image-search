"""
Reusable card components for the instant-share PC mini-window.
Provides styled containers with background, border, and padding.
Matches React design: rounded-xl (12px), slate-50 surface.
"""

from PySide6.QtCore import Qt
from PySide6.QtGui import QFont, QFontMetrics
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout, QWidget

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Spacing,
    Typography,
)
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    _make_font,
    apply_body_label,
    apply_caption_label,
    apply_pin_digit_label,
)


class CardContainer(QFrame):
    """Styled card container with surface background and border."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("CardContainer")
        self.setStyleSheet(f"""
            #CardContainer {{
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
    """File info card showing type badge, name, size, and path.

    Type badge uses primary blue background with white text.
    Includes a right chevron indicator.
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("CardContainer")

        row = QHBoxLayout()
        row.setSpacing(Spacing.ITEM_GAP)

        # File type badge (blue square with rounded corners)
        self._type_badge = QLabel()
        self._type_badge.setAlignment(Qt.AlignCenter)
        self._type_badge.setFixedSize(40, 40)
        self._type_badge.setStyleSheet(f"""
            background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 #a1c4fd, stop:1 #c2e9fb);
            color: #1d4ed8;
            border-radius: 8px;
            font-size: 8pt;
            font-weight: 900;
        """)
        row.addWidget(self._type_badge)

        # File info
        info_layout = QVBoxLayout()
        info_layout.setSpacing(2)

        self._name_label = QLabel()
        apply_caption_label(self._name_label)
        self._name_label.setWordWrap(False)
        self._name_label.setMaximumWidth(220)
        self._name_label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; font-weight: bold; background: transparent;")
        info_layout.addWidget(self._name_label)

        self._meta_label = QLabel()
        apply_caption_label(self._meta_label)
        info_layout.addWidget(self._meta_label)

        row.addLayout(info_layout, 1)

        # Right chevron indicator
        self._chevron_label = QLabel("")
        # Use SVG for chevron
        from PySide6.QtSvgWidgets import QSvgWidget
        self._chevron_svg = QSvgWidget()
        self._chevron_svg.load(bytearray('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#cbd5e1" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>', "utf-8"))
        self._chevron_svg.setFixedSize(14, 14)
        self._chevron_svg.setStyleSheet("background: transparent; border: none;")
        row.addWidget(self._chevron_svg)
        chevron_font = _make_font(20, weight=QFont.Weight.Normal)
        self._chevron_label.setFont(chevron_font)
        self._chevron_label.setStyleSheet(f"color: {Colors.TEXT_MUTED}; background: transparent;")
        

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
        self._meta_label.setText(f"{size} \u00b7 {path}" if size else path)


class PINCard(CardContainer):
    """PIN display card with large, spaced digits.

    Uses JetBrains Mono (or Menlo fallback) at 32px with extra bold weight.
    Digits are spaced generously for clarity.
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("CardContainer")
        self._layout.setAlignment(Qt.AlignCenter)

        self._pin_label = QLabel()
        self._pin_label.setAlignment(Qt.AlignCenter)
        apply_pin_digit_label(self._pin_label)
        self._layout.addWidget(self._pin_label)

    def set_pin(self, pin: str) -> None:
        """Display the PIN with generous spacing between digits."""
        self._pin_label.setText(pin)


class TextPreviewCard(CardContainer):
    """Text preview card with monospace font."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("CardContainer")

        self._text_label = QLabel()
        self._text_label.setWordWrap(True)
        self._text_label.setStyleSheet(f"""
            color: {Colors.TEXT_PRIMARY};
            font-family: "Menlo", "Courier New", monospace;
            font-size: {Typography.CAPTION_SIZE}px;
            background: transparent;
        """)
        self._layout.addWidget(self._text_label)

    def set_text(self, text: str, max_chars: int = 200) -> None:
        """Display truncated text preview."""
        display = text[:max_chars]
        if len(text) > max_chars:
            display += "..."
        self._text_label.setText(display)
