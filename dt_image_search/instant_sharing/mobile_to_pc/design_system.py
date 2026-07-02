"""
Design system tokens for the instant-share PC mini-window.

All colors, typography, and spacing constants live here.
Light mode palette matching the React figma design reference.
"""


class Colors:
    """Color tokens matching the React figma design specification."""

    # Backgrounds
    BACKGROUND = "#FFFFFF"
    SURFACE = "#f8fafc"  # slate-50

    # Primary buttons
    PRIMARY_DARK = "#0f172a"  # slate-900 (Show in Finder, Retry, Done)
    PRIMARY_BLUE = "#2563eb"  # blue-600 (Copy Text, Send)

    # Secondary / ghost buttons — no border, light gray bg
    GHOST_BG = "#f1f5f9"
    GHOST_TEXT = "#475569"  # slate-600

    # Text colors
    TEXT_PRIMARY = "#0f172a"    # slate-900
    TEXT_SECONDARY = "#94a3b8"  # slate-400
    TEXT_MUTED = "#94a3b8"      # slate-400

    # Status colors
    SUCCESS = "#059669"    # emerald-600
    SUCCESS_BG = "#d1fae5"
    ERROR = "#ef4444"       # red-500
    ERROR_BG = "#fef2f2"       # red-50
    WARNING = "#d97706"     # amber-600 (lock icon color)
    WARNING_BG = "#fffbeb"  # amber-50 (lock icon background)
    WARNING_LIGHT = "#fbbf24" # amber-400 (pulse dot)

    # UI elements
    BORDER = "#e2e8f0"       # slate-200
    BORDER_LIGHT = "#cbd5e1"  # slate-300
    DISABLED_BG = "#f1f5f9"
    DISABLED_TEXT = "#94a3b8"
    QUEUED = "#cbd5e1"

    # Badges
    BADGE_GREEN = "#059669"
    BADGE_BLUE = "#2563eb"

    # Progress bar
    PROGRESS_TRACK = "#f1f5f9"   # slate-100
    PROGRESS_FILL = "#3b82f6"    # blue-500

    # Hover
    HOVER_LIGHT = "#f1f5f9"       # slate-100 for ghost hover
    PRIMARY_DARK_HOVER = "#1e293b"  # slightly lighter dark
    PRIMARY_BLUE_HOVER = "#1d4ed8"  # blue-700


class Typography:
    """Font size and weight tokens (all values in pixels to match React design)."""

    HEADING_SIZE = 20       # text-xl
    SUBTITLE_SIZE = 12      # text-xs
    BODY_SIZE = 14          # text-sm
    CAPTION_SIZE = 12       # text-xs
    LABEL_SIZE = 10
    PIN_DIGIT_SIZE = 48     # text-5xl
    BUTTON_SIZE = 14        # text-sm
    BADGE_SIZE = 11


class Spacing:
    """Layout spacing tokens."""

    WINDOW_PADDING = 24
    SECTION_GAP = 20
    ITEM_GAP = 12
    CARD_PADDING = 14
    BUTTON_PADDING_V = 10   # py-2.5
    BUTTON_PADDING_H = 16   # px-4
    BUTTON_RADIUS = 12      # rounded-xl
    CARD_RADIUS = 16        # rounded-2xl
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
