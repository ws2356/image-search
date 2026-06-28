"""
Qt stylesheet helpers for consistent button, card, and text styling.
Uses design system tokens for consistent visual appearance.
"""

from PySide6.QtWidgets import QPushButton, QLabel, QWidget
from PySide6.QtGui import QFont

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Typography,
    Spacing,
)


def _make_font(size: int, bold: bool = False, family: str = "") -> QFont:
    font = QFont()
    if family:
        font.setFamily(family)
    font.setPointSize(size)
    font.setBold(bold)
    return font


def apply_button_style(
    button: QPushButton,
    variant: str = "primary_dark",
    *,
    enabled: bool = True,
) -> None:
    """Apply design system styling to a button.

    Variants: primary_dark, primary_blue, ghost, disabled
    """
    if not enabled:
        variant = "disabled"

    styles = {
        "primary_dark": f"""
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
        """,
        "primary_blue": f"""
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
        """,
        "ghost": f"""
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
        """,
        "disabled": f"""
            QPushButton {{
                background-color: {Colors.DISABLED_BG};
                color: {Colors.DISABLED_TEXT};
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}pt;
                font-weight: bold;
                min-height: {Spacing.BUTTON_HEIGHT - 24}px;
            }}
        """,
    }
    button.setStyleSheet(styles.get(variant, styles["primary_dark"]))


def apply_card_style(widget: QWidget) -> None:
    """Apply card container styling to a widget."""
    widget.setStyleSheet(f"""
        QWidget {{
            background-color: {Colors.SURFACE};
            border: 1px solid {Colors.BORDER};
            border-radius: {Spacing.CARD_RADIUS}px;
            padding: {Spacing.CARD_PADDING}px;
        }}
    """)


def apply_heading_label(label: QLabel, size: int | None = None) -> None:
    """Apply heading typography to a label."""
    label.setFont(_make_font(size or Typography.HEADING_SIZE, bold=Typography.BOLD))
    label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")


def apply_subtitle_label(label: QLabel) -> None:
    """Apply subtitle typography to a label."""
    label.setFont(_make_font(Typography.SUBTITLE_SIZE))
    label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")


def apply_body_label(label: QLabel) -> None:
    """Apply body typography to a label."""
    label.setFont(_make_font(Typography.BODY_SIZE))
    label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")


def apply_caption_label(label: QLabel) -> None:
    """Apply caption typography to a label."""
    label.setFont(_make_font(Typography.CAPTION_SIZE))
    label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")


def apply_pin_digit_label(label: QLabel) -> None:
    """Apply PIN digit styling to a label."""
    font = QFont("Menlo", Typography.PIN_DIGIT_SIZE)
    font.setBold(True)
    label.setFont(font)
    label.setAlignment(label.alignment())
    label.setStyleSheet(f"""
        color: {Colors.TEXT_PRIMARY};
        background: transparent;
        letter-spacing: 2px;
    """)
