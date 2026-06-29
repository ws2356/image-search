"""
Qt stylesheet helpers for consistent button, card, and text styling.
Uses design system tokens for consistent visual appearance.
Updated to match React figma design reference.
"""

from PySide6.QtGui import QFont
from PySide6.QtWidgets import QLabel, QPushButton, QWidget

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Spacing,
    Typography,
)


def _make_font(size: int, weight: QFont.Weight = QFont.Weight.Normal, family: str = "") -> QFont:
    """Create a QFont with pixel-based size and specified weight."""
    font = QFont()
    if family:
        font.setFamily(family)
    font.setPixelSize(size)
    font.setWeight(weight)
    return font


def apply_button_style(
    button: QPushButton,
    variant: str = "primary_dark",
    *,
    enabled: bool = True,
) -> None:
    """Apply design system styling to a button.

    Variants: primary_dark, primary_blue, ghost, disabled
    Matches React: font-size 14px, font-weight 500 (medium), rounded-xl (12px)
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
                font-size: {Typography.BUTTON_SIZE}px;
                font-weight: 500; /* medium */
                min-height: 20px;
            }}
            QPushButton:hover {{
                background-color: {Colors.PRIMARY_DARK_HOVER};
            }}
        """,
        "primary_blue": f"""
            QPushButton {{
                background-color: {Colors.PRIMARY_BLUE};
                color: white;
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}px;
                font-weight: 500; /* medium */
                min-height: 20px;
            }}
            QPushButton:hover {{
                background-color: {Colors.PRIMARY_BLUE_HOVER};
            }}
        """,
        "ghost": f"""
            QPushButton {{
                background-color: {Colors.GHOST_BG};
                color: {Colors.GHOST_TEXT};
                border: 1px solid rgba(226, 232, 240, 0.6);
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}px;
                font-weight: 500; /* medium */
                min-height: 20px;
            }}
            QPushButton:hover {{
                background-color: {Colors.BORDER};
            }}
        """,
        "disabled": f"""
            QPushButton {{
                background-color: {Colors.DISABLED_BG};
                color: {Colors.DISABLED_TEXT};
                border: none;
                border-radius: {Spacing.BUTTON_RADIUS}px;
                padding: {Spacing.BUTTON_PADDING_V}px {Spacing.BUTTON_PADDING_H}px;
                font-size: {Typography.BUTTON_SIZE}px;
                font-weight: 500; /* medium */
                min-height: 20px;
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


def apply_heading_label(label: QLabel) -> None:
    """Apply heading typography to a label: 20px, bold (#1e293b)."""
    font = _make_font(Typography.HEADING_SIZE, weight=QFont.Weight.Bold)
    label.setFont(font)
    label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")


def apply_subtitle_label(label: QLabel) -> None:
    """Apply subtitle typography to a label: 12px, normal (#94a3b8)."""
    font = _make_font(Typography.SUBTITLE_SIZE, weight=QFont.Weight.Normal)
    label.setFont(font)
    label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")


def apply_body_label(label: QLabel) -> None:
    """Apply body typography to a label: 14px, normal (#1e293b)."""
    font = _make_font(Typography.BODY_SIZE, weight=QFont.Weight.Normal)
    label.setFont(font)
    label.setStyleSheet(f"color: {Colors.TEXT_PRIMARY}; background: transparent;")


def apply_caption_label(label: QLabel) -> None:
    """Apply caption typography to a label: 12px, normal (#64748b)."""
    font = _make_font(Typography.CAPTION_SIZE, weight=QFont.Weight.Normal)
    label.setFont(font)
    label.setStyleSheet(f"color: {Colors.TEXT_SECONDARY}; background: transparent;")


def apply_pin_digit_label(label: QLabel) -> None:
    """Apply PIN digit styling: 48px, weight 900, tracking 14px, JetBrains Mono."""
    font = _make_font(
        Typography.PIN_DIGIT_SIZE,
        weight=QFont.Weight.Black,
        family='"JetBrains Mono", "Menlo", monospace',
    )
    font.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 14)
    label.setFont(font)
    label.setAlignment(label.alignment())
    label.setStyleSheet(f"""
        color: {Colors.TEXT_PRIMARY};
        background: transparent;
    """)
