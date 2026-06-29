from __future__ import annotations

import logging
import socket
from typing import Callable

from PIL import Image
from PySide6.QtCore import Qt, QTimer, QRect
from PySide6.QtGui import QImage, QPainter, QPen, QColor, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QHBoxLayout,
    QLabel,
    QScrollArea,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.lan_discovery import get_lan_ip_addresses
from dt_image_search.instant_sharing.mobile_to_pc.components.buttons import GhostButton
from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Typography,
    Spacing,
)
from dt_image_search.instant_sharing.mobile_to_pc.styles import (
    _make_font,
    apply_heading_label,
    apply_subtitle_label,
    apply_caption_label,
)
from dt_image_search.instant_sharing.qr_trigger_handler import StashEntry

try:
    import qrcode
except Exception:
    qrcode = None

_logger = logging.getLogger(__name__)

WINDOW_WIDTH = 400
WINDOW_HEIGHT = 580
QR_SIZE = 240

# Corner bracket visual parameters
_BRACKET_LENGTH = 30
_BRACKET_WIDTH = 3
_BRACKET_GAP = 4


def build_qr_url(
    *,
    ips: list[str],
    port: int,
    tls_port: int,
    session_id: str,
    opt_code: str
) -> str:
    ips_str = ",".join(ips)
    return f"https://dl.boldman.net/share?ips={ips_str}&p={port}&sp={tls_port}&sid={session_id}&opt={opt_code}"


def render_qr_pixmap(payload: str, size: int) -> QPixmap:
    pixmap = QPixmap(size, size)
    if qrcode is not None:
        try:
            qr = qrcode.QRCode(border=2, box_size=8)
            qr.add_data(payload)
            qr.make(fit=True)
            qr_image = qr.make_image(fill_color="black", back_color="white").convert("RGBA")
            qr_image = qr_image.resize((size, size), Image.Resampling.NEAREST)
            rgba = qr_image.tobytes("raw", "RGBA")
            qimage = QImage(rgba, size, size, QImage.Format_RGBA8888).copy()
            pixmap = QPixmap.fromImage(qimage)
        except Exception as exc:
            _logger.warning("Failed to render QR code: %s", exc)
    if pixmap.isNull():
        pixmap.fill(Qt.GlobalColor.white)
        painter = QPainter(pixmap)
        painter.setPen(Qt.GlobalColor.gray)
        font = painter.font()
        font.setPointSize(10)
        painter.setFont(font)
        painter.drawText(pixmap.rect(), Qt.AlignCenter, "QR Unavailable")
        painter.end()
    return pixmap


class QRCodeContainer(QWidget):
    """Custom widget that wraps a QR QLabel and paints 4 blue corner brackets."""

    def __init__(self, qr_label: QLabel, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._qr_label = qr_label
        self.setFixedSize(QR_SIZE + 2 * (_BRACKET_LENGTH + _BRACKET_GAP),
                          QR_SIZE + 2 * (_BRACKET_LENGTH + _BRACKET_GAP))

        inner_layout = QVBoxLayout(self)
        inner_layout.setContentsMargins(
            _BRACKET_LENGTH + _BRACKET_GAP,
            _BRACKET_LENGTH + _BRACKET_GAP,
            _BRACKET_LENGTH + _BRACKET_GAP,
            _BRACKET_LENGTH + _BRACKET_GAP,
        )
        inner_layout.setSpacing(0)
        inner_layout.addWidget(self._qr_label)

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        pen = QPen(QColor(Colors.PRIMARY_BLUE))
        pen.setWidth(_BRACKET_WIDTH)
        painter.setPen(pen)

        w = self.width()
        h = self.height()
        gap = _BRACKET_GAP
        length = _BRACKET_LENGTH

        # Top-left
        painter.drawLine(gap, gap + length, gap, gap)
        painter.drawLine(gap, gap, gap + length, gap)
        # Top-right
        painter.drawLine(w - gap - length, gap, w - gap, gap)
        painter.drawLine(w - gap, gap, w - gap, gap + length)
        # Bottom-left
        painter.drawLine(gap, h - gap - length, gap, h - gap)
        painter.drawLine(gap, h - gap, gap + length, h - gap)
        # Bottom-right
        painter.drawLine(w - gap - length, h - gap, w - gap, h - gap)
        painter.drawLine(w - gap, h - gap - length, w - gap, h - gap)

        painter.end()


class QRTriggerMiniWindow(QDialog):
    def __init__(
        self,
        stash: StashEntry,
        *,
        session_id: str = "",
        pc_name: str = "",
        pc_port: int,
        pc_tls_port: int,
        device_id: str = "",
        lan_ips: list[str] | None = None,
        on_cancel: Callable[[str], None] | None = None,
        parent: QWidget | None = None,
        file_count: int = 0,
        filenames: list[str] | None = None,
    ) -> None:
        super().__init__(parent)
        self._stash = stash
        self._session_id = session_id
        self._pc_name = pc_name or socket.gethostname()
        self._pc_port = pc_port
        self._pc_tls_port = pc_tls_port
        self._device_id = device_id
        self._lan_ips = lan_ips or get_lan_ip_addresses()
        self._on_cancel = on_cancel
        self._auto_close_timer: QTimer | None = None
        self._claimed = False
        self._expired = False
        self._file_count = file_count
        self._filenames = filenames or []
        self._setup_ui()

    @property
    def stash_id(self) -> str:
        return self._stash.stash_id

    def on_claimed(self, peer_device_name: str = "") -> None:
        self._claimed = True
        if peer_device_name:
            self._message_label.setText(f"Delivered to {peer_device_name}")
        else:
            self._message_label.setText("Delivered")
        self._qr_container.hide()
        self._cancel_button.hide()
        self._dismiss_button.show()
        QTimer.singleShot(4000, self.close)

    def on_expired(self) -> None:
        self._expired = True
        self._message_label.setText("Expired")
        self._qr_container.hide()
        self._cancel_button.hide()
        self._dismiss_button.show()
        QTimer.singleShot(10000, self.close)

    def _setup_ui(self) -> None:
        self.setWindowTitle("Send to Your Phone")
        self.setFixedSize(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.setAttribute(Qt.WA_DeleteOnClose)

        app_icon = QApplication.windowIcon()
        if not app_icon.isNull():
            self.setWindowIcon(app_icon)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(
            Spacing.WINDOW_PADDING, Spacing.WINDOW_PADDING,
            Spacing.WINDOW_PADDING, Spacing.WINDOW_PADDING,
        )
        layout.setSpacing(Spacing.ITEM_GAP)

        # Heading: 18pt bold, TEXT_PRIMARY
        title_label = QLabel("Scan to Receive")
        title_label.setAlignment(Qt.AlignCenter)
        apply_heading_label(title_label)
        layout.addWidget(title_label)

        # Subtitle: 14pt, TEXT_SECONDARY
        subtitle_label = QLabel(f"from {self._pc_name}")
        subtitle_label.setAlignment(Qt.AlignCenter)
        apply_subtitle_label(subtitle_label)
        layout.addWidget(subtitle_label)

        # Batch file count and filename list (shown when file_count > 1)
        if self._file_count > 1:
            layout.addSpacing(4)
            count_label = QLabel(f"Sharing {self._file_count} files")
            count_label.setAlignment(Qt.AlignCenter)
            count_label.setFont(_make_font(13, bold=True))
            count_label.setStyleSheet(
                f"color: {Colors.TEXT_PRIMARY}; background: transparent;"
            )
            layout.addWidget(count_label)

            # Scrollable filename list, truncated to 10 shown items
            visible_count = min(self._file_count, 10)
            file_list_widget = QWidget()
            file_list_layout = QVBoxLayout(file_list_widget)
            file_list_layout.setContentsMargins(8, 4, 8, 4)
            file_list_layout.setSpacing(2)

            for i, filename in enumerate(self._filenames[:visible_count]):
                file_label = QLabel(filename)
                file_label.setStyleSheet(
                    f"color: {Colors.TEXT_SECONDARY}; font-size: 12px; background: transparent;"
                )
                file_list_layout.addWidget(file_label)

            if self._file_count > 10:
                more_label = QLabel(f"+{self._file_count - 10} more files...")
                more_label.setStyleSheet(
                    f"color: {Colors.TEXT_MUTED}; font-size: 11px; font-style: italic; background: transparent;"
                )
                file_list_layout.addWidget(more_label)

            scroll = QScrollArea()
            scroll.setWidget(file_list_widget)
            scroll.setWidgetResizable(True)
            scroll.setMaximumHeight(140)
            scroll.setStyleSheet(
                f"QScrollArea {{ border: 1px solid {Colors.BORDER}; border-radius: {Spacing.CARD_RADIUS}px; background: transparent; }}"
            )
            layout.addWidget(scroll)

        layout.addSpacing(8)

        # QR code inside bracket container
        self._qr_label = QLabel()
        self._qr_label.setAlignment(Qt.AlignCenter)
        self._qr_label.setFixedSize(QR_SIZE, QR_SIZE)
        self._qr_label.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        self._qr_label.setStyleSheet(
            f"background-color: {Colors.BACKGROUND}; border: 1px solid {Colors.BORDER_LIGHT}; border-radius: {Spacing.CARD_RADIUS}px;"
        )
        self._qr_label.setText("Generating QR...")

        self._qr_container = QRCodeContainer(self._qr_label)
        layout.addWidget(self._qr_container, alignment=Qt.AlignCenter)

        layout.addSpacing(8)

        # Instruction message — caption styling
        self._message_label = QLabel(
            'Scan this QR code with your iPhone or the <b>AuBackup</b> app to receive the shared content.'
        )
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setTextFormat(Qt.RichText)
        apply_caption_label(self._message_label)
        layout.addWidget(self._message_label)

        # IP:port pill badge
        first_ip = self._lan_ips[0] if self._lan_ips else "0.0.0.0"
        pill_label = QLabel(f"{first_ip}:{self._pc_port}")
        pill_label.setAlignment(Qt.AlignCenter)
        pill_label.setFont(_make_font(Typography.BADGE_SIZE))
        pill_label.setStyleSheet(
            f"""
            QLabel {{
                background-color: {Colors.SURFACE};
                border: 1px solid {Colors.BORDER};
                border-radius: 12px;
                padding: 3px 6px;
                color: {Colors.TEXT_SECONDARY};
            }}
            """
        )
        # Wrap in a container so the pill centers properly
        pill_container = QHBoxLayout()
        pill_container.setAlignment(Qt.AlignCenter)
        pill_container.addWidget(pill_label)
        layout.addLayout(pill_container)

        # Buttons — GhostButton for Cancel and Close
        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self._cancel_button = GhostButton("Cancel")
        self._cancel_button.clicked.connect(self._on_cancel_clicked)
        button_layout.addWidget(self._cancel_button)

        self._dismiss_button = GhostButton("Close")
        self._dismiss_button.clicked.connect(self.close)
        self._dismiss_button.setVisible(False)
        button_layout.addWidget(self._dismiss_button)

        layout.addLayout(button_layout)

    def _on_cancel_clicked(self) -> None:
        if self._on_cancel is not None:
            self._on_cancel(self._stash.stash_id)
        self.close()

    def show_qr(self) -> None:
        payload = build_qr_url(
            ips=self._lan_ips,
            port=self._pc_port,
            tls_port=self._pc_tls_port,
            session_id=self._session_id,
            opt_code=self._stash.opt_code
        )
        pixmap = render_qr_pixmap(payload, QR_SIZE)
        self.set_qr_pixmap(pixmap)

    def set_qr_pixmap(self, pixmap: QPixmap) -> None:
        self._qr_label.setPixmap(pixmap)
        self._qr_label.setText("")

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
            self._auto_close_timer = None
        super().closeEvent(event)
