"""
Snapshot tests for instant-share mobile-to-PC and PC-to-mobile flows.

Tests use pytest-qt and pytest-snapshot to capture and compare widget screenshots.
"""

import os
import tempfile
from io import BytesIO

import pytest
from PySide6.QtCore import QBuffer, QIODevice
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import QApplication

from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
)
from dt_image_search.instant_sharing.mini_window import (
    InstantShareMiniWindow,
    WINDOW_WIDTH,
    WINDOW_HEIGHT,
)
from dt_image_search.instant_sharing.qr_trigger_mini_window import (
    QRTriggerMiniWindow,
    QR_SIZE,
    WINDOW_WIDTH as QR_WINDOW_WIDTH,
    WINDOW_HEIGHT as QR_WINDOW_HEIGHT,
)
from dt_image_search.instant_sharing.qr_trigger_handler import StashEntry


def capture_widget_as_png(widget) -> bytes:
    """Capture a Qt widget as PNG bytes."""
    pixmap = widget.grab()
    qimage = pixmap.toImage()

    buffer = QBuffer()
    buffer.open(QIODevice.WriteOnly)
    qimage.save(buffer, "PNG")
    return buffer.data().data()


class TestMobileToPCFlows:
    """Snapshot tests for mobile-to-PC instant-share flows."""

    def test_pin_code_display(self, qapp_instance, snapshot, snapshot_dir):
        """Test PIN code verification page."""
        window = InstantShareMiniWindow()
        window.show()

        # Set PIN code state
        state = MiniWindowState(
            phase=MiniWindowPhase.DISPLAYING_PIN,
            device_name="iPhone",
            payload_label="shared text",
            pin_code="3847",
        )
        window.apply_session_event(
            state="displaying_pin",
            device_name="iPhone",
            payload_class="text",
        )
        window._state.pin_code = "3847"
        window._refresh_ui()

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_pin_code.png")

        window.close()

    def test_loading_connecting(self, qapp_instance, snapshot, snapshot_dir):
        """Test loading/connecting page."""
        window = InstantShareMiniWindow()
        window.show()

        # Set connecting state
        window.apply_session_event(
            state="connecting",
            device_name="iPhone",
            payload_class="text",
        )

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_loading_connecting.png")

        window.close()

    def test_loading_transferring(self, qapp_instance, snapshot, snapshot_dir):
        """Test loading/transferring page."""
        window = InstantShareMiniWindow()
        window.show()

        # Set transferring state
        window.apply_session_event(
            state="transferring",
            device_name="iPhone",
            payload_class="image",
            image_count=5,
            received_count=3,
        )

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_loading_transferring.png")

        window.close()

    def test_completion_text_received(self, qapp_instance, snapshot, snapshot_dir):
        """Test completion page with text content received."""
        window = InstantShareMiniWindow()
        window.show()

        # Set success state with text content
        window.apply_session_event(
            state="done",
            device_name="iPhone",
            payload_class="text",
            text_content="Hello from Mac!\nThis is a shared text message.",
        )

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_completion_text.png")

        window.close()

    def test_completion_file_received(self, qapp_instance, snapshot, snapshot_dir):
        """Test completion page with file received."""
        window = InstantShareMiniWindow()
        window.show()

        # Set success state with a fixed filename (no temp path shown in UI)
        window.apply_session_event(
            state="done",
            device_name="iPhone",
            payload_class="file",
            file_path="/Users/ws2356/Downloads/vacation_photo.jpg",
        )

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_completion_file.png")

        window.close()

    def test_completion_error(self, qapp_instance, snapshot, snapshot_dir):
        """Test error state."""
        window = InstantShareMiniWindow()
        window.show()

        # Set error state
        window.apply_session_event(
            state="failed",
            device_name="iPhone",
            payload_class="text",
            error_message="Connection lost. Please try again.",
        )

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "mobile_to_pc_completion_error.png")

        window.close()


class TestPCToMobileFlows:
    """Snapshot tests for PC-to-mobile instant-share flows (QR trigger)."""

    def test_qr_code_display(self, qapp_instance, snapshot, snapshot_dir):
        """Test QR code display window."""
        # Create a mock stash entry
        stash = StashEntry(
            stash_id="test-stash-123",
            content_type="text/plain",
            content="Hello from PC",
            opt_code="123456",
        )

        window = QRTriggerMiniWindow(
            stash=stash,
            session_id="test-session-123",
            pc_name="MacBook-Pro.local",
            pc_port=8080,
            pc_tls_port=8443,
            device_id="test-device",
            lan_ips=["192.168.1.100"],
        )
        window.show()

        # Generate and set QR code
        window.show_qr()

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "pc_to_mobile_qr_code.png")

        window.close()

    def test_qr_code_with_files(self, qapp_instance, snapshot, snapshot_dir):
        """Test QR code display with multiple files."""
        # Create a mock stash entry
        stash = StashEntry(
            stash_id="test-stash-456",
            content_type="multi/image",
            content=None,
            opt_code="789012",
        )

        window = QRTriggerMiniWindow(
            stash=stash,
            session_id="test-session-456",
            pc_name="MacBook-Pro.local",
            pc_port=8080,
            pc_tls_port=8443,
            device_id="test-device",
            lan_ips=["192.168.1.100"],
            file_count=3,
            filenames=["vacation_photo.jpg", "report.pdf", "design_assets.zip"],
        )
        window.show()

        # Generate and set QR code
        window.show_qr()

        # Capture snapshot
        app = QApplication.instance()
        app.processEvents()

        image_bytes = capture_widget_as_png(window)
        snapshot.snapshot_dir = snapshot_dir
        snapshot.assert_match(image_bytes, "pc_to_mobile_qr_code_files.png")

        window.close()
