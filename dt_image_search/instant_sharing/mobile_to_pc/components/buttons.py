"""
Reusable button components for the instant-share PC mini-window.
Supports primary dark, primary blue, and ghost/secondary variants.
"""

from PySide6.QtWidgets import QPushButton

from dt_image_search.instant_sharing.mobile_to_pc.styles import apply_button_style


class PrimaryDarkButton(QPushButton):
    """Dark navy primary button (Show in Finder, Retry, Done)."""

    def __init__(self, text: str, parent=None) -> None:
        super().__init__(text, parent)
        apply_button_style(self, "primary_dark")


class PrimaryBlueButton(QPushButton):
    """Blue primary button (Copy Text, Copy to Clipboard, Send)."""

    def __init__(self, text: str, parent=None) -> None:
        super().__init__(text, parent)
        apply_button_style(self, "primary_blue")


class GhostButton(QPushButton):
    """Ghost/secondary button (Close, Cancel)."""

    def __init__(self, text: str, parent=None) -> None:
        super().__init__(text, parent)
        apply_button_style(self, "ghost")
