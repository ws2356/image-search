"""
Reusable text label components for the instant-share PC mini-window.
"""

from PySide6.QtWidgets import QLabel

from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    apply_heading_label,
    apply_subtitle_label,
    apply_body_label,
    apply_caption_label,
)


class HeadingLabel(QLabel):
    """Large heading label."""

    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        apply_heading_label(self)
        self.setWordWrap(True)


class SubtitleLabel(QLabel):
    """Subtitle / description label."""

    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        apply_subtitle_label(self)
        self.setWordWrap(True)


class BodyLabel(QLabel):
    """Body text label."""

    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        apply_body_label(self)
        self.setWordWrap(True)


class CaptionLabel(QLabel):
    """Caption / metadata label."""

    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        apply_caption_label(self)


class BadgeLabel(QLabel):
    """Small badge label (e.g., "1 found", "Scanning...")."""

    def __init__(self, text: str = "", color: str = "#34C759", parent=None) -> None:
        super().__init__(text, parent)
        self.setStyleSheet(f"""
            color: {color};
            font-size: 11pt;
            font-weight: bold;
            background: transparent;
        """)
