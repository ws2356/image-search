from __future__ import annotations

from datetime import datetime, timezone

from PySide6.QtCore import QRect, QSize, Qt
from PySide6.QtGui import QColor, QFont, QFontMetrics, QPainter
from PySide6.QtWidgets import QApplication, QStyle, QStyleOptionViewItem, QStyledItemDelegate

from dt_image_search.base.FolderTreeModel import FolderTreeModel


class FolderTreeItemDelegate(QStyledItemDelegate):
    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        if bool(index.data(FolderTreeModel.SECTION_ROLE)):
            self._paint_section_row(painter, option, index)
            return

        parent_index = index.parent()
        is_mobile_top_level = bool(
            parent_index.isValid()
            and parent_index.data(FolderTreeModel.SECTION_ROLE)
            and parent_index.data(FolderTreeModel.SECTION_KIND_ROLE) == FolderTreeModel._MOBILE_SECTION_KIND
        )
        if is_mobile_top_level:
            self._paint_mobile_row(painter, option, index)
            return

        super().paint(painter, option, index)

    def sizeHint(self, option: QStyleOptionViewItem, index) -> QSize:
        if bool(index.data(FolderTreeModel.SECTION_ROLE)):
            return QSize(super().sizeHint(option, index).width(), 22)

        parent_index = index.parent()
        is_mobile_top_level = bool(
            parent_index.isValid()
            and parent_index.data(FolderTreeModel.SECTION_ROLE)
            and parent_index.data(FolderTreeModel.SECTION_KIND_ROLE) == FolderTreeModel._MOBILE_SECTION_KIND
        )
        if not is_mobile_top_level:
            return super().sizeHint(option, index)

        transfer_state = index.data(FolderTreeModel.MOBILE_TRANSFER_STATE_ROLE)
        return QSize(super().sizeHint(option, index).width(), 54 if transfer_state == "transferring" else 40)

    def _paint_section_row(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        section_kind = index.data(FolderTreeModel.SECTION_KIND_ROLE)
        background_color = QColor("#F8F8F8") if section_kind == FolderTreeModel._LOCAL_SECTION_KIND else QColor("#F5F5F5")

        painter.save()
        painter.fillRect(option.rect, background_color)
        painter.setPen(QColor("#E8E8E8") if section_kind == FolderTreeModel._MOBILE_SECTION_KIND else QColor("#EEEEEE"))
        painter.drawLine(option.rect.bottomLeft(), option.rect.bottomRight())
        if section_kind == FolderTreeModel._MOBILE_SECTION_KIND:
            painter.drawLine(option.rect.topLeft(), option.rect.topRight())
        painter.restore()

        painter.save()
        text_rect = option.rect.adjusted(8, 2, -8, -2)
        section_font = QFont(option.font)
        section_font.setPointSize(max(section_font.pointSize() - 1, 9))
        section_font.setBold(True)
        painter.setFont(section_font)
        painter.setPen(QColor("#6B7280"))
        painter.drawText(text_rect, Qt.AlignLeft | Qt.AlignVCenter, str(index.data(Qt.DisplayRole) or "").upper())
        painter.restore()

    def _paint_mobile_row(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        title_text = str(index.data(Qt.DisplayRole) or "")
        transfer_state = str(index.data(FolderTreeModel.MOBILE_TRANSFER_STATE_ROLE) or "")
        transferred_count = int(index.data(FolderTreeModel.MOBILE_TRANSFERRED_COUNT_ROLE) or 0)
        last_backup_at = index.data(FolderTreeModel.MOBILE_LAST_BACKUP_AT_ROLE)
        platform = str(index.data(FolderTreeModel.MOBILE_PLATFORM_ROLE) or "")

        painter.save()
        if option.state & QStyle.State_Selected:
            painter.fillRect(option.rect, QColor("#E8F0FD"))
        elif option.state & QStyle.State_MouseOver:
            painter.fillRect(option.rect, QColor("#F5F5F5"))
        else:
            painter.fillRect(option.rect, QColor("#FFFFFF"))
        painter.setPen(QColor("#F0F0F0"))
        painter.drawLine(option.rect.bottomLeft(), option.rect.bottomRight())

        content_rect = option.rect.adjusted(8, 3, -8, -4)
        icon_text = _platform_icon(platform)
        icon_rect = QRect(content_rect.left(), content_rect.top(), 14, 14)
        icon_font = QFont(option.font)
        icon_font.setPointSize(max(icon_font.pointSize(), 10))
        painter.setFont(icon_font)
        painter.setPen(QColor("#374151"))
        painter.drawText(icon_rect, Qt.AlignCenter, icon_text)

        title_font = QFont(option.font)
        title_font.setPointSize(max(title_font.pointSize(), 10))
        title_font.setBold(False)
        painter.setFont(title_font)
        painter.setPen(QColor("#111827"))

        title_rect = QRect(icon_rect.right() + 6, content_rect.top(), content_rect.width() - 20, 18)
        if transfer_state == "transferring":
            badge_rect = self._draw_transferring_badge(painter, content_rect)
            title_rect.setRight(badge_rect.left() - 6)
        elided_title = QFontMetrics(title_font).elidedText(title_text, Qt.ElideRight, max(title_rect.width(), 0))
        painter.drawText(title_rect, Qt.AlignLeft | Qt.AlignVCenter, elided_title)

        subtitle_font = QFont(option.font)
        subtitle_font.setPointSize(max(subtitle_font.pointSize() - 1, 9))
        painter.setFont(subtitle_font)
        painter.setPen(QColor("#6B7280"))

        subtitle_text = self._subtitle_text(
            transfer_state=transfer_state,
            transferred_count=transferred_count,
            last_backup_at=last_backup_at,
        )
        subtitle_top = title_rect.bottom() + 1
        subtitle_rect = QRect(icon_rect.right() + 6, subtitle_top, content_rect.width() - 20, 14)
        subtitle_metrics = QFontMetrics(subtitle_font)
        subtitle = subtitle_metrics.elidedText(subtitle_text, Qt.ElideRight, max(subtitle_rect.width(), 0))
        painter.drawText(subtitle_rect, Qt.AlignLeft | Qt.AlignVCenter, subtitle)

        if transfer_state == "transferring":
            bar_rect = QRect(content_rect.left(), subtitle_rect.bottom() + 2, content_rect.width(), 4)
            self._draw_progress_bar(painter, bar_rect, transferred_count=transferred_count)

        painter.restore()

    def _draw_item_background(self, painter: QPainter, option: QStyleOptionViewItem, index) -> None:
        style_option = QStyleOptionViewItem(option)
        self.initStyleOption(style_option, index)
        style_option.text = ""
        style = style_option.widget.style() if style_option.widget else QApplication.style()
        style.drawControl(QStyle.CE_ItemViewItem, style_option, painter, style_option.widget)

    @staticmethod
    def _draw_transferring_badge(painter: QPainter, content_rect: QRect) -> QRect:
        badge_font = painter.font()
        badge_font.setPointSize(max(badge_font.pointSize() - 1, 9))
        badge_font.setBold(True)
        painter.setFont(badge_font)

        badge_text = "\u21bb Transferring"
        text_metrics = QFontMetrics(badge_font)
        badge_height = 18
        badge_width = text_metrics.horizontalAdvance(badge_text) + 12
        badge_rect = QRect(content_rect.right() - badge_width, content_rect.top(), badge_width, badge_height)

        painter.setPen(QColor("#93C5FD"))
        painter.setBrush(QColor("#DBEAFE"))
        painter.drawRoundedRect(badge_rect, 9, 9)

        painter.setPen(QColor("#1D4ED8"))
        painter.drawText(badge_rect, Qt.AlignCenter, badge_text)
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
    def _subtitle_text(*, transfer_state: str, transferred_count: int, last_backup_at: object) -> str:
        if transfer_state == "transferring":
            return f"{max(transferred_count, 0)} files transferred"
        return _last_backup_subtitle(last_backup_at)


def _last_backup_subtitle(last_backup_at: object) -> str:
    if not isinstance(last_backup_at, str) or not last_backup_at:
        return "Not backup yet"

    parsed_time = _parse_iso_datetime(last_backup_at)
    if parsed_time is None:
        return "Not backup yet"
    return f"Last backup: {parsed_time.strftime('%Y-%m-%d %H:%M:%S')}"


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
        return parsed_time.replace(tzinfo=timezone.utc)
    return parsed_time.astimezone(timezone.utc)


def _platform_icon(platform: str) -> str:
    normalized_platform = platform.strip().lower()
    if normalized_platform == "ios":
        return "\U0001F34E"
    if normalized_platform == "android":
        return "\U0001F916"
    return "\U0001F4F1"
