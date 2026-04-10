from __future__ import annotations

from datetime import datetime
from typing import Callable

from PIL import Image
from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QColor, QFont, QImage, QPainter, QPixmap
from PySide6.QtWidgets import (
    QFileDialog,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.mobile.mobile_pairing_service import MobilePairingService, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import (
    MobilePairingSessionDraft,
    MobilePairingToken,
    MobilePlatform,
    MobileSourceType,
    platform_display_name,
)
from dt_image_search.telemetry.telemetry_client import log

try:
    import qrcode
except Exception:
    qrcode = None


class SourceSelectionDialog(QDialog):
    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self._selected_source: MobileSourceType | None = None
        self.setWindowTitle("Add Folder")
        self.setModal(True)
        self.resize(620, 280)

        layout = QVBoxLayout(self)
        layout.setSpacing(16)

        title = QLabel("Choose a source")
        title_font = QFont()
        title_font.setPointSize(15)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)

        subtitle = QLabel(
            "Local Device keeps the existing folder-indexing flow. Mobile Device starts a paired backup flow where USB is preferred and Wi-Fi LAN is also supported."
        )
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #4b5563;")
        layout.addWidget(subtitle)

        button_row = QHBoxLayout()
        button_row.setSpacing(12)
        button_row.addWidget(
            self._build_source_button(
                title="Local Device",
                description="Index a folder that already exists on this computer.",
                source=MobileSourceType.LOCAL_DEVICE,
            )
        )
        button_row.addWidget(
            self._build_source_button(
                title="Mobile Device",
                description="Choose a desktop destination, then pair a phone or tablet for local transfer.",
                source=MobileSourceType.MOBILE_DEVICE,
            )
        )
        layout.addLayout(button_row)

        cancel_button = QPushButton("Cancel")
        cancel_button.clicked.connect(self.reject)
        cancel_button.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        layout.addWidget(cancel_button, alignment=Qt.AlignRight)

    def _build_source_button(self, title: str, description: str, source: MobileSourceType) -> QPushButton:
        button = QPushButton(f"{title}\n\n{description}")
        button.setMinimumSize(280, 170)
        button.setCursor(Qt.PointingHandCursor)
        button.setStyleSheet(
            """
            QPushButton {
                border: 1px solid #d1d5db;
                border-radius: 12px;
                padding: 18px;
                text-align: left;
                font-size: 14px;
                background: #ffffff;
            }
            QPushButton:hover {
                border-color: #2563eb;
                background: #eff6ff;
            }
            """
        )
        button.clicked.connect(lambda: self._select_source(source))
        return button

    def _select_source(self, source: MobileSourceType) -> None:
        self._selected_source = source
        self.accept()

    @classmethod
    def select_source(cls, parent: QWidget | None = None) -> MobileSourceType | None:
        dialog = cls(parent)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            return dialog._selected_source
        return None


class PairingQrCard(QFrame):
    def __init__(
        self,
        platform: MobilePlatform,
        token: MobilePairingToken,
        on_refresh: Callable[[MobilePlatform], MobilePairingToken],
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._platform = platform
        self._token = token
        self._on_refresh = on_refresh
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet("border: 1px solid #d1d5db; border-radius: 12px; background: #ffffff;")

        layout = QVBoxLayout(self)
        layout.setSpacing(10)

        title = QLabel(platform_display_name(platform))
        title_font = QFont()
        title_font.setBold(True)
        title_font.setPointSize(12)
        title.setFont(title_font)
        layout.addWidget(title)

        self.qr_label = QLabel()
        self.qr_label.setFixedSize(220, 220)
        self.qr_label.setAlignment(Qt.AlignCenter)
        self.qr_label.setStyleSheet("background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;")
        layout.addWidget(self.qr_label, alignment=Qt.AlignCenter)

        self.status_label = QLabel()
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)

        self.token_label = QLabel()
        self.token_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.token_label.setStyleSheet("color: #4b5563;")
        layout.addWidget(self.token_label)

        self.refresh_button = QPushButton("Refresh QR")
        self.refresh_button.setCursor(Qt.PointingHandCursor)
        self.refresh_button.clicked.connect(self._refresh_token)
        self.refresh_button.hide()
        layout.addWidget(self.refresh_button, alignment=Qt.AlignLeft)

        instructions = QLabel(self._instructions_text(platform))
        instructions.setWordWrap(True)
        instructions.setStyleSheet("color: #4b5563;")
        layout.addWidget(instructions)

        self.set_token(token)

    def _instructions_text(self, platform: MobilePlatform) -> str:
        if platform == MobilePlatform.ANDROID:
            return "Scan from Album Transporter on Android. USB is preferred when available and Wi-Fi LAN remains available as fallback."
        return "Scan from Album Transporter on iPhone or iPad. USB is preferred when available and Wi-Fi LAN remains available as fallback."

    def set_token(self, token: MobilePairingToken) -> None:
        self._token = token
        pixmap = _render_qr_pixmap(token.payload, size=220)
        self.qr_label.setPixmap(pixmap)
        self.token_label.setText(f"Token {token.token_id[:8]} · secret {token.bootstrap_secret[:10]}…")
        self.update_clock(datetime.now(token.expires_at.tzinfo))

    def update_clock(self, now: datetime) -> None:
        expired = self._token.is_expired(now)
        if expired:
            self.status_label.setText("QR expired. Refresh to generate a new pairing token.")
            self.refresh_button.show()
            self.qr_label.setStyleSheet("background: #f3f4f6; border: 1px solid #f59e0b; border-radius: 8px;")
        else:
            seconds_remaining = self._token.seconds_remaining(now)
            minutes = seconds_remaining // 60
            seconds = seconds_remaining % 60
            self.status_label.setText(f"Expires in {minutes:02d}:{seconds:02d}")
            self.refresh_button.hide()
            self.qr_label.setStyleSheet("background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;")

    def _refresh_token(self) -> None:
        refreshed_token = self._on_refresh(self._platform)
        self.set_token(refreshed_token)


class MobilePairingDialog(QDialog):
    def __init__(
        self,
        pairing_service: MobilePairingService,
        pairing_session: MobilePairingSessionDraft,
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._pairing_service = pairing_service
        self._pairing_session = pairing_session
        self.setWindowTitle("Pair Mobile Device")
        self.setModal(True)
        self.resize(860, 620)

        layout = QVBoxLayout(self)
        layout.setSpacing(14)

        title = QLabel("Pair Mobile Device")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)

        subtitle = QLabel(
            "Keep the desktop pairing window open while the mobile app claims the session. The QR payload now points at a live local bootstrap endpoint and the desktop persists accepted trust state for later resume work."
        )
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #4b5563;")
        layout.addWidget(subtitle)

        destination_row = QHBoxLayout()
        destination_caption = QLabel("Destination parent")
        destination_caption.setStyleSheet("font-weight: 600;")
        destination_row.addWidget(destination_caption)

        self.destination_label = QLabel(pairing_session.destination_parent)
        self.destination_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.destination_label.setWordWrap(True)
        destination_row.addWidget(self.destination_label, stretch=1)

        self.change_button = QPushButton("Change")
        self.change_button.clicked.connect(self._change_destination)
        destination_row.addWidget(self.change_button)
        layout.addLayout(destination_row)

        qr_row = QHBoxLayout()
        qr_row.setSpacing(14)
        self.android_card = PairingQrCard(
            platform=MobilePlatform.ANDROID,
            token=pairing_session.token_for(MobilePlatform.ANDROID),
            on_refresh=self._refresh_platform_token,
        )
        self.ios_card = PairingQrCard(
            platform=MobilePlatform.IOS,
            token=pairing_session.token_for(MobilePlatform.IOS),
            on_refresh=self._refresh_platform_token,
        )
        qr_row.addWidget(self.android_card)
        qr_row.addWidget(self.ios_card)
        layout.addLayout(qr_row)

        helper_text = QLabel(
            "Use the companion app to scan or paste the platform-specific QR link. Each code carries a distinct bootstrap secret and expires independently after fifteen minutes."
        )
        helper_text.setWordWrap(True)
        helper_text.setStyleSheet("color: #4b5563;")
        layout.addWidget(helper_text)

        self.session_status_label = QLabel("Waiting for a mobile device to claim this pairing session.")
        self.session_status_label.setWordWrap(True)
        self.session_status_label.setStyleSheet("font-weight: 600; color: #1f2937;")
        layout.addWidget(self.session_status_label)

        self.session_details_label = QLabel(
            f"Desktop endpoint: {pairing_service.endpoint_url}\nDestination folder will be resolved after the mobile device identity is accepted."
        )
        self.session_details_label.setWordWrap(True)
        self.session_details_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.session_details_label.setStyleSheet("color: #4b5563;")
        layout.addWidget(self.session_details_label)

        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.reject)
        layout.addWidget(self.close_button, alignment=Qt.AlignRight)

        self._clock_timer = QTimer(self)
        self._clock_timer.setInterval(1000)
        self._clock_timer.timeout.connect(self._update_clock)
        self._clock_timer.start()
        self._update_clock()

    @property
    def pairing_session(self) -> MobilePairingSessionDraft:
        return self._pairing_session

    def _update_clock(self) -> None:
        now = datetime.now(self._pairing_session.created_at.tzinfo)
        self.android_card.update_clock(now)
        self.ios_card.update_clock(now)
        self._update_pairing_result()

    def _refresh_platform_token(self, platform: MobilePlatform) -> MobilePairingToken:
        token = self._pairing_service.refresh_token(platform)
        log(
            "info",
            message=(
                f"MobilePairingDialog/_refresh_platform_token: refreshed {platform.value} token "
                f"for session {self._pairing_session.session_id}"
            ),
        )
        return token

    def _update_pairing_result(self) -> None:
        pairing_result = self._pairing_service.current_result()
        if pairing_result.state == PairingResultState.ACCEPTED:
            self.session_status_label.setText(pairing_result.message)
            details = [
                f"Device: {pairing_result.device_name or 'Unknown'}",
                f"Transport: {pairing_result.transport or 'Unknown'}",
            ]
            if pairing_result.folder_path:
                details.append(f"Desktop folder: {pairing_result.folder_path}")
            self.session_details_label.setText("\n".join(details))
            self.session_status_label.setStyleSheet("font-weight: 600; color: #065f46;")
            self.change_button.setEnabled(False)
            self.close_button.setText("Done")
            return

        if pairing_result.state == PairingResultState.EXPIRED:
            self.session_status_label.setText(pairing_result.message)
            self.session_details_label.setText("Refresh the appropriate QR code on desktop, then retry the mobile pairing flow.")
            self.session_status_label.setStyleSheet("font-weight: 600; color: #b45309;")
            self.close_button.setText("Close")
            return

        if pairing_result.state == PairingResultState.REJECTED:
            self.session_status_label.setText(pairing_result.message)
            self.session_details_label.setText("Desktop rejected the request. Generate a fresh QR code and retry pairing.")
            self.session_status_label.setStyleSheet("font-weight: 600; color: #991b1b;")
            self.close_button.setText("Close")
            return

        self.session_status_label.setText(pairing_result.message)
        self.session_details_label.setText(
            f"Desktop endpoint: {self._pairing_service.endpoint_url}\nDestination folder will be resolved after the mobile device identity is accepted."
        )
        self.session_status_label.setStyleSheet("font-weight: 600; color: #1f2937;")
        self.change_button.setEnabled(True)
        self.close_button.setText("Close")

    def _change_destination(self) -> None:
        selected_directory = QFileDialog.getExistingDirectory(
            self,
            "Select Mobile Backup Parent Folder",
            self._pairing_session.destination_parent,
        )
        if not selected_directory:
            return
        self._pairing_session.set_destination_parent(selected_directory)
        self.destination_label.setText(self._pairing_session.destination_parent)
        log(
            "info",
            message=(
                "MobilePairingDialog/_change_destination: updated destination parent "
                f"for session {self._pairing_session.session_id}"
            ),
        )

    def reject(self) -> None:
        if self._pairing_service.current_result().state == PairingResultState.ACCEPTED:
            self._clock_timer.stop()
            super().accept()
            return
        should_close = QMessageBox.question(
            self,
            "Close Pairing",
            "Close the mobile pairing dialog? This cancels the current desktop pairing intent and you will need to start again.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if should_close != QMessageBox.StandardButton.Yes:
            return
        self._clock_timer.stop()
        super().reject()


def _render_qr_pixmap(payload: str, size: int) -> QPixmap:
    if qrcode is not None:
        try:
            qr_code = qrcode.QRCode(border=2, box_size=8)
            qr_code.add_data(payload)
            qr_code.make(fit=True)
            qr_image = qr_code.make_image(fill_color="black", back_color="white").convert("RGBA")
            qr_image = qr_image.resize((size, size), Image.Resampling.NEAREST)
            return _pil_image_to_pixmap(qr_image)
        except Exception as exc:
            log("warning", message=f"mobile_dialogs/_render_qr_pixmap: failed to render QR code: {exc}")
    return _build_placeholder_pixmap(size=size)


def _pil_image_to_pixmap(image: Image.Image) -> QPixmap:
    rgba_image = image.convert("RGBA")
    data = rgba_image.tobytes("raw", "RGBA")
    qimage = QImage(data, rgba_image.width, rgba_image.height, QImage.Format_RGBA8888).copy()
    return QPixmap.fromImage(qimage)


def _build_placeholder_pixmap(size: int) -> QPixmap:
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.white)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setPen(QColor("#d1d5db"))
    painter.drawRect(4, 4, size - 8, size - 8)
    painter.setPen(QColor("#111827"))
    font = painter.font()
    font.setPointSize(14)
    font.setBold(True)
    painter.setFont(font)
    painter.drawText(pixmap.rect(), Qt.AlignCenter, "QR\nUnavailable")
    painter.end()
    return pixmap
