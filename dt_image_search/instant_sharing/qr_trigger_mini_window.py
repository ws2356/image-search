from __future__ import annotations

import logging
import socket
from typing import Callable

from PIL import Image
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QImage, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.lan_discovery import get_lan_ip_addresses
from dt_image_search.instant_sharing.qr_trigger_handler import StashEntry

try:
    import qrcode
except Exception:
    qrcode = None

_logger = logging.getLogger(__name__)

WINDOW_WIDTH = 400
WINDOW_HEIGHT = 580
QR_SIZE = 240


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
        self._qr_label.hide()
        self._cancel_button.hide()
        self._dismiss_button.show()
        QTimer.singleShot(4000, self.close)

    def on_expired(self) -> None:
        self._expired = True
        self._message_label.setText("Expired")
        self._qr_label.hide()
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
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(12)

        title_label = QLabel("Scan to Receive")
        title_label.setAlignment(Qt.AlignCenter)
        font = title_label.font()
        font.setPointSize(20)
        font.setBold(True)
        title_label.setFont(font)
        layout.addWidget(title_label)

        subtitle_label = QLabel(f"from <b>{self._pc_name}</b>")
        subtitle_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(subtitle_label)

        layout.addSpacing(8)

        self._qr_label = QLabel()
        self._qr_label.setAlignment(Qt.AlignCenter)
        self._qr_label.setFixedSize(QR_SIZE, QR_SIZE)
        self._qr_label.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        self._qr_label.setStyleSheet(
            "background-color: white; border: 1px solid #d1d5db; border-radius: 8px;"
        )
        self._qr_label.setText("Generating QR...")
        layout.addWidget(self._qr_label, alignment=Qt.AlignCenter)

        layout.addSpacing(8)

        self._message_label = QLabel('Scan this QR code with your iPhone or the <b>AuBackup</b> app to receive the shared content.')
        self._message_label.setAlignment(Qt.AlignCenter)
        self._message_label.setWordWrap(True)
        self._message_label.setTextFormat(Qt.RichText)
        layout.addWidget(self._message_label)

        # layout.addStretch()

        ips_str = ", ".join(self._lan_ips)
        port_label = QLabel(f"PC Address: {ips_str}:{self._pc_port}")
        port_label.setAlignment(Qt.AlignCenter)
        port_label.setStyleSheet("color: #9CA3AF; font-size: 11px;")
        layout.addWidget(port_label)

        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self._cancel_button = QPushButton("Cancel")
        self._cancel_button.clicked.connect(self._on_cancel_clicked)
        button_layout.addWidget(self._cancel_button)

        self._dismiss_button = QPushButton("Close")
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

    def closeEvent(self, event) -> None:
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
            self._auto_close_timer = None
        super().closeEvent(event)
