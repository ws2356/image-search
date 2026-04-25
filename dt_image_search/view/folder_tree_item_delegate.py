from __future__ import annotations

from datetime import datetime, timezone
from importlib.resources import as_file, files

from PySide6.QtCore import QRect, QSize, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QFontMetrics, QPainter, QPixmap
from PySide6.QtWidgets import QAbstractItemView, QStyle, QStyleOptionViewItem, QStyledItemDelegate

from dt_image_search.base.FolderTreeModel import FolderTreeModel

_TREE_DEFAULT_ROW_BACKGROUND_COLOR = QColor("#FFFFFF")
_TREE_SELECTED_ROW_BACKGROUND_COLOR = QColor("#E8F0FD")
_TREE_ROW_DIVIDER_COLOR = QColor("#D8E6FB")
_IOS_PLATFORM_ICON_FILENAME = "ios_bitten_apple_gray.png"
_IOS_PLATFORM_ICON_CACHE: QPixmap | None = None
_IOS_PLATFORM_ICON_LOAD_ATTEMPTED = False


class FolderTreeItemDelegate(QStyledItemDelegate):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._spinner_angle = 0
        self._spinner_timer = QTimer(self)
        self._spinner_timer.setInterval(120)
        self._spinner_timer.timeout.connect(self._advance_spinner)
        self._spinner_timer.start()

    def _advance_spinner(self) -> None:
        self._spinner_angle = (self._spinner_angle + 24) % 360
        parent_view = self.parent()
        if isinstance(parent_view, QAbstractItemView):
            parent_view.viewport().update()

    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        if bool(index.data(FolderTreeModel.SECTION_ROLE)):
            self._paint_section_row(painter, option, index)
            return

        parent_index = index.parent()
        is_top_level_folder = bool(
            parent_index.isValid()
            and parent_index.data(FolderTreeModel.SECTION_ROLE)
        )
        if not is_top_level_folder:
            super().paint(painter, option, index)
            return

        section_kind = parent_index.data(FolderTreeModel.SECTION_KIND_ROLE)
        if section_kind == FolderTreeModel._MOBILE_SECTION_KIND:
            self._paint_mobile_row(painter, option, index)
            return
        if section_kind == FolderTreeModel._LOCAL_SECTION_KIND:
            self._paint_local_root_row(painter, option, index)
            return

        super().paint(painter, option, index)

    def sizeHint(self, option: QStyleOptionViewItem, index) -> QSize:
        if bool(index.data(FolderTreeModel.SECTION_ROLE)):
            return QSize(super().sizeHint(option, index).width(), 22)

        parent_index = index.parent()
        is_top_level_folder = bool(
            parent_index.isValid()
            and parent_index.data(FolderTreeModel.SECTION_ROLE)
        )
        if not is_top_level_folder or parent_index.data(FolderTreeModel.SECTION_KIND_ROLE) != FolderTreeModel._MOBILE_SECTION_KIND:
            return super().sizeHint(option, index)

        transfer_state = index.data(FolderTreeModel.MOBILE_TRANSFER_STATE_ROLE)
        return QSize(super().sizeHint(option, index).width(), 54 if transfer_state == "transferring" else 40)

    def _paint_section_row(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        painter.save()
        painter.fillRect(option.rect, _TREE_DEFAULT_ROW_BACKGROUND_COLOR)
        painter.setPen(_TREE_ROW_DIVIDER_COLOR)
        painter.drawLine(option.rect.bottomLeft(), option.rect.bottomRight())
        painter.restore()

        painter.save()
        text_rect = option.rect.adjusted(8, 2, -8, -2)
        section_font = QFont(option.font)
        section_font.setPointSize(max(section_font.pointSize() - 1, 9))
        section_font.setBold(True)
        painter.setFont(section_font)
        painter.setPen(QColor("#888888"))
        painter.drawText(text_rect, Qt.AlignLeft | Qt.AlignVCenter, str(index.data(Qt.DisplayRole) or "").upper())
        painter.restore()

    def _paint_mobile_row(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        title_text = str(index.data(Qt.DisplayRole) or "")
        transfer_state = str(index.data(FolderTreeModel.MOBILE_TRANSFER_STATE_ROLE) or "")
        transferred_count = int(index.data(FolderTreeModel.MOBILE_TRANSFERRED_COUNT_ROLE) or 0)
        last_backup_at = index.data(FolderTreeModel.MOBILE_LAST_BACKUP_AT_ROLE)
        last_transfer_status = index.data(FolderTreeModel.MOBILE_LAST_TRANSFER_STATUS_ROLE)
        last_transfer_at = index.data(FolderTreeModel.MOBILE_LAST_TRANSFER_AT_ROLE)
        platform = str(index.data(FolderTreeModel.MOBILE_PLATFORM_ROLE) or "")

        painter.save()
        row_background = _TREE_SELECTED_ROW_BACKGROUND_COLOR if option.state & QStyle.State_Selected else _TREE_DEFAULT_ROW_BACKGROUND_COLOR
        painter.fillRect(option.rect, row_background)
        painter.setPen(_TREE_ROW_DIVIDER_COLOR)
        painter.drawLine(option.rect.bottomLeft(), option.rect.bottomRight())

        content_rect = option.rect.adjusted(0, 3, -8, -4)
        icon_pixmap = _platform_icon_pixmap(platform)

        title_font = QFont(option.font)
        title_font.setPointSize(max(title_font.pointSize(), 10))
        title_font.setBold(False)
        painter.setFont(title_font)
        painter.setPen(QColor("#1A1A1A"))

        title_rect = QRect(content_rect.left(), content_rect.top(), content_rect.width(), 18)
        if icon_pixmap is not None:
            icon_size = 16
            icon_rect = QRect(content_rect.left(), title_rect.center().y() - (icon_size // 2), icon_size, icon_size)
            scaled_icon = icon_pixmap.scaled(icon_size, icon_size, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            icon_x = icon_rect.left() + max((icon_rect.width() - scaled_icon.width()) // 2, 0)
            icon_y = icon_rect.top() + max((icon_rect.height() - scaled_icon.height()) // 2, 0)
            painter.drawPixmap(icon_x, icon_y, scaled_icon)
            title_rect.setLeft(icon_rect.right() + 5)
            title_with_icon = title_text
        else:
            icon_text = _platform_icon(platform)
            title_with_icon = f"{icon_text} {title_text}".strip()
        if transfer_state == "transferring":
            badge_rect = self._draw_transferring_badge(painter, content_rect)
            title_rect.setRight(badge_rect.left() - 6)
        elided_title = QFontMetrics(title_font).elidedText(title_with_icon, Qt.ElideRight, max(title_rect.width(), 0))
        painter.drawText(title_rect, Qt.AlignLeft | Qt.AlignVCenter, elided_title)

        subtitle_font = QFont(option.font)
        subtitle_font.setPointSize(max(subtitle_font.pointSize() - 1, 9))
        painter.setFont(subtitle_font)
        painter.setPen(QColor("#888888"))

        subtitle_text = self._subtitle_text(
            transfer_state=transfer_state,
            transferred_count=transferred_count,
            last_backup_at=last_backup_at,
            last_transfer_status=last_transfer_status,
            last_transfer_at=last_transfer_at,
        )
        subtitle_top = title_rect.bottom() + 1
        subtitle_rect = QRect(content_rect.left(), subtitle_top, content_rect.width(), 14)
        subtitle_metrics = QFontMetrics(subtitle_font)
        subtitle = subtitle_metrics.elidedText(subtitle_text, Qt.ElideRight, max(subtitle_rect.width(), 0))
        painter.drawText(subtitle_rect, Qt.AlignLeft | Qt.AlignVCenter, subtitle)

        if transfer_state == "transferring":
            bar_rect = QRect(content_rect.left(), subtitle_rect.bottom() + 2, content_rect.width(), 4)
            self._draw_progress_bar(painter, bar_rect, transferred_count=transferred_count)

        painter.restore()

    def _paint_local_root_row(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        title_text = str(index.data(Qt.DisplayRole) or "")

        painter.save()
        row_background = _TREE_SELECTED_ROW_BACKGROUND_COLOR if option.state & QStyle.State_Selected else _TREE_DEFAULT_ROW_BACKGROUND_COLOR
        painter.fillRect(option.rect, row_background)
        painter.setPen(_TREE_ROW_DIVIDER_COLOR)
        painter.drawLine(option.rect.bottomLeft(), option.rect.bottomRight())

        title_font = QFont(option.font)
        title_font.setPointSize(max(title_font.pointSize(), 10))
        title_font.setBold(False)
        painter.setFont(title_font)
        painter.setPen(QColor("#333333"))

        content_rect = option.rect.adjusted(0, 2, -8, -2)
        title_with_icon = f"{_local_folder_icon()} {title_text}".strip()
        elided_title = QFontMetrics(title_font).elidedText(title_with_icon, Qt.ElideRight, max(content_rect.width(), 0))
        painter.drawText(content_rect, Qt.AlignLeft | Qt.AlignVCenter, elided_title)

        painter.restore()

    def _draw_transferring_badge(self, painter: QPainter, content_rect: QRect) -> QRect:
        badge_font = painter.font()
        badge_font.setPointSize(max(badge_font.pointSize() - 1, 9))
        badge_font.setBold(True)
        painter.setFont(badge_font)

        badge_text = "Transferring"
        text_metrics = QFontMetrics(badge_font)
        badge_height = 18
        icon_box_size = 14
        icon_spacing = 4
        badge_width = text_metrics.horizontalAdvance(badge_text) + icon_box_size + icon_spacing + 12
        badge_rect = QRect(content_rect.right() - badge_width, content_rect.top(), badge_width, badge_height)

        painter.setPen(QColor("#93C5FD"))
        painter.setBrush(QColor("#DBEAFE"))
        painter.drawRoundedRect(badge_rect, 9, 9)

        icon_center_x = badge_rect.left() + 4 + icon_box_size // 2
        icon_center_y = badge_rect.center().y()
        painter.save()
        painter.translate(icon_center_x, icon_center_y)
        painter.rotate(self._spinner_angle)
        painter.setPen(QColor("#1D4ED8"))
        icon_font = QFont(badge_font)
        icon_font.setBold(False)
        icon_font.setPointSize(max(icon_font.pointSize(), 10))
        painter.setFont(icon_font)
        half_icon_box = icon_box_size // 2
        painter.drawText(QRect(-half_icon_box, -half_icon_box, icon_box_size, icon_box_size), Qt.AlignCenter, "\u21bb")
        painter.restore()

        painter.setFont(badge_font)
        painter.setPen(QColor("#1D4ED8"))
        text_rect = badge_rect.adjusted(icon_box_size + icon_spacing + 2, 0, -6, 0)
        painter.drawText(text_rect, Qt.AlignLeft | Qt.AlignVCenter, badge_text)
        return badge_rect

    @staticmethod
    def _draw_progress_bar(painter: QPainter, bar_rect: QRect, *, transferred_count: int) -> None:
        if not bar_rect.isValid():
            return
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor("#DBEAFE"))
        painter.drawRoundedRect(bar_rect, 2, 2)

        if transferred_count <= 0:
            progress_ratio = 0.28
        else:
            progress_ratio = min(0.9, max(0.2, transferred_count / (transferred_count + 20.0)))
        fill_width = max(2, int(bar_rect.width() * progress_ratio))
        fill_rect = QRect(bar_rect.left(), bar_rect.top(), fill_width, bar_rect.height())
        painter.setBrush(QColor("#3B82F6"))
        painter.drawRoundedRect(fill_rect, 2, 2)

    @staticmethod
    def _subtitle_text(
        *,
        transfer_state: str,
        transferred_count: int,
        last_backup_at: object,
        last_transfer_status: object,
        last_transfer_at: object,
    ) -> str:
        if transfer_state == "transferring":
            return f"{max(transferred_count, 0)} files transferred"
        if isinstance(last_transfer_status, str) and last_transfer_status == "stopped_by_mobile":
            return _stopped_backup_subtitle(last_transfer_at)
        if isinstance(last_transfer_status, str) and last_transfer_status == "failed":
            return _failed_backup_subtitle(last_transfer_at)
        if isinstance(last_transfer_status, str) and last_transfer_status == "completed":
            return _completed_backup_subtitle(last_backup_at, last_transfer_at)
        return _last_backup_subtitle(last_backup_at)


def _stopped_backup_subtitle(last_transfer_at: object) -> str:
    return _timestamped_backup_subtitle(
        last_transfer_at,
        prefix="Backup stopped",
        fallback="Backup stopped",
    )


def _failed_backup_subtitle(last_transfer_at: object) -> str:
    return _timestamped_backup_subtitle(
        last_transfer_at,
        prefix="Backup failed",
        fallback="Backup failed",
    )


def _completed_backup_subtitle(last_backup_at: object, last_transfer_at: object) -> str:
    if isinstance(last_backup_at, str) and last_backup_at:
        return _last_backup_subtitle(last_backup_at)
    return _timestamped_backup_subtitle(
        last_transfer_at,
        prefix="Last backup",
        fallback="Not backup yet",
    )


def _last_backup_subtitle(last_backup_at: object) -> str:
    if not isinstance(last_backup_at, str) or not last_backup_at:
        return "Not backup yet"

    parsed_time = _parse_iso_datetime(last_backup_at)
    if parsed_time is None:
        return "Not backup yet"
    return f"Last backup: {parsed_time.strftime('%Y-%m-%d %H:%M:%S')}"


def _timestamped_backup_subtitle(
    iso_value: object,
    *,
    prefix: str,
    fallback: str,
) -> str:
    if not isinstance(iso_value, str) or not iso_value:
        return fallback

    parsed_time = _parse_iso_datetime(iso_value)
    if parsed_time is None:
        return fallback
    return f"{prefix}: {parsed_time.strftime('%Y-%m-%d %H:%M:%S')}"


def _parse_iso_datetime(iso_value: str) -> datetime | None:
    normalized_value = iso_value.strip()
    if not normalized_value:
        return None
    if normalized_value.endswith("Z"):
        normalized_value = normalized_value[:-1] + "+00:00"
    try:
        parsed_time = datetime.fromisoformat(normalized_value)
    except ValueError:
        return None
    if parsed_time.tzinfo is None:
        parsed_time = parsed_time.replace(tzinfo=timezone.utc)
    local_timezone = datetime.now().astimezone().tzinfo
    if local_timezone is None:
        return parsed_time
    return parsed_time.astimezone(local_timezone)


def _platform_icon(platform: str) -> str:
    normalized_platform = platform.strip().lower()
    if normalized_platform == "ios":
        return "\U0001F34E"
    if normalized_platform == "android":
        return "\U0001F916"
    return "\U0001F4F1"


def _local_folder_icon() -> str:
    return "\U0001F4C1"


def _platform_icon_pixmap(platform: str) -> QPixmap | None:
    normalized_platform = platform.strip().lower()
    if normalized_platform != "ios":
        return None

    global _IOS_PLATFORM_ICON_LOAD_ATTEMPTED
    global _IOS_PLATFORM_ICON_CACHE

    if _IOS_PLATFORM_ICON_LOAD_ATTEMPTED:
        return _IOS_PLATFORM_ICON_CACHE

    _IOS_PLATFORM_ICON_LOAD_ATTEMPTED = True
    resource = files("dt_image_search").joinpath("resources", _IOS_PLATFORM_ICON_FILENAME)
    if not resource.is_file():
        return None

    with as_file(resource) as resource_path:
        loaded_icon = QPixmap(str(resource_path))
    if loaded_icon.isNull():
        return None

    _IOS_PLATFORM_ICON_CACHE = loaded_icon
    return _IOS_PLATFORM_ICON_CACHE
