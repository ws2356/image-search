"""
Design system tokens for the instant-share PC mini-window.

All colors, typography, and spacing constants live here.
Light mode palette — dark mode support deferred.
"""


class Colors:
    """Color tokens matching the new design specification."""

    # Backgrounds
    BACKGROUND = "#FFFFFF"
    SURFACE = "#F5F7FA"
    SURFACE_HOVER = "#EDF0F5"

    # Primary buttons
    PRIMARY_DARK = "#2563EB"  # Navy buttons (Show in Finder, Retry, Done)
    PRIMARY_BLUE = "#2563EB"  # Blue action buttons (Copy Text, Send)

    # Secondary / ghost buttons
    GHOST_BG = "transparent"
    GHOST_TEXT = "#1B2A4A"
    GHOST_BORDER = "#E5E7EB"

    # Text colors
    TEXT_PRIMARY = "#1B2A4A"
    TEXT_SECONDARY = "#6B7280"
    TEXT_MUTED = "#9CA3AF"

    # Status colors
    SUCCESS = "#34C759"
    SUCCESS_BG = "#D4F5DD"
    ERROR = "#FF3B30"
    ERROR_BG = "#FDE8E8"
    WARNING_BG = "#FFF3E0"  # Lock icon background

    # UI elements
    BORDER = "#E5E7EB"
    BORDER_LIGHT = "#D1D5DB"
    DISABLED_BG = "#E8ECF0"
    DISABLED_TEXT = "#A0AEC0"
    QUEUED = "#C7C7CC"

    # Badges
    BADGE_GREEN = "#34C759"
    BADGE_BLUE = "#2563EB"

    # Progress bar
    PROGRESS_TRACK = "#E5E7EB"
    PROGRESS_FILL = "#2563EB"


class Typography:
    """Font size and weight tokens."""

    # Sizes (in points)
    HEADING_SIZE = 18
    SUBTITLE_SIZE = 14
    BODY_SIZE = 14
    CAPTION_SIZE = 12
    LABEL_SIZE = 10
    PIN_DIGIT_SIZE = 28
    BUTTON_SIZE = 14
    BADGE_SIZE = 11

    # Weights
    BOLD = True
    SEMIBOLD = True
    MEDIUM = True
    REGULAR = False


class Spacing:
    """Layout spacing tokens."""

    WINDOW_PADDING = 24
    SECTION_GAP = 20
    ITEM_GAP = 12
    CARD_PADDING = 14
    BUTTON_PADDING_V = 12
    BUTTON_PADDING_H = 20
    BUTTON_HEIGHT = 44
    BUTTON_RADIUS = 22  # pill shape
    CARD_RADIUS = 10
    ICON_SIZE_LARGE = 56
    ICON_SIZE_SMALL = 14


class Icons:
    """Icon identifiers (mapped to emoji or SVG paths)."""

    LOCK = "🔒"
    CHECKMARK = "✅"
    WARNING = "⚠️"
    REFRESH = "🔄"
    FOLDER = "📁"
    COPY = "📋"
    CHEVRON_RIGHT = "›"
    WIFI = "📶"
    COMPUTER = "🖥️"
    IMAGE = "🖼️"
