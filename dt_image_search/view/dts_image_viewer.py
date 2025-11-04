from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem,
    QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QSizePolicy, QLabel
)
from PySide6.QtGui import QPixmap, QWheelEvent, QMouseEvent, QKeySequence, QShortcut
from PySide6.QtCore import Qt, QPointF, Signal, QTimer
import os
from pathlib import Path
from typing import Optional

try:
    from .image_navigator import ImageNavigator, FolderBasedNavigator
except ImportError:
    # Fallback for relative import issues
    from dt_image_search.view.image_navigator import ImageNavigator, FolderBasedNavigator

class ImageViewerWidget(QGraphicsView):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setScene(QGraphicsScene(self))
        self.pixmap_item = QGraphicsPixmapItem()
        self.scene().addItem(self.pixmap_item)

        self.setDragMode(QGraphicsView.NoDrag)  # We'll handle dragging manually
        self.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.AnchorViewCenter)

        self._zoom = 0
        self._dragging = False
        self._last_pos = None
        self._empty = True

        self.setBackgroundBrush(Qt.black)

    def set_image(self, image_path):
        from PIL import Image, ImageFile
        from PySide6.QtGui import QImage, QPixmap
        ImageFile.LOAD_TRUNCATED_IMAGES = True
        pixmap = QPixmap()
        try:
            pil_image = Image.open(image_path).convert("RGBA")
            data = pil_image.tobytes("raw", "RGBA")
            qimage = QImage(data, pil_image.width, pil_image.height, QImage.Format_RGBA8888)
            pixmap = QPixmap.fromImage(qimage)
        except Exception as e:
            # Fallback to QPixmap loading (may fail for truncated images)
            pixmap = QPixmap(image_path)
        if pixmap.isNull():
            self.pixmap_item.setPixmap(QPixmap())
            self._empty = True
        else:
            self._empty = False
            self.pixmap_item.setPixmap(pixmap)
            self.scene().setSceneRect(pixmap.rect())
            self.reset_view()

    def reset_view(self):
        self._zoom = 0
        self.fitInView(self.sceneRect(), Qt.KeepAspectRatio)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton and not self._empty:
            self._dragging = True
            self._last_pos = event.pos()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._dragging and self._last_pos:
            # Calculate the movement delta in view coordinates
            delta = event.pos() - self._last_pos
            
            # Convert to scene coordinates to move the view
            # Invert the delta because we want to move the view in the opposite direction
            # of the mouse movement to simulate dragging the image
            h_scroll = self.horizontalScrollBar()
            v_scroll = self.verticalScrollBar()
            
            h_scroll.setValue(h_scroll.value() - delta.x())
            v_scroll.setValue(v_scroll.value() - delta.y())

            self._last_pos = event.pos()

        # Forward mouse move event to parent to show overlays
        if self.parent():
            self.parent().mouseMoveEvent(event)
        
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._dragging = False
            self._last_pos = None
        super().mouseReleaseEvent(event)

    def wheelEvent(self, event: QWheelEvent):
        if self._empty:
            return
        zoom_in = event.angleDelta().y() > 0
        factor = 1.25 if zoom_in else 0.8
        self._zoom += 1 if zoom_in else -1
        if self._zoom < -10:
            self._zoom = -10
        elif self._zoom > 20:
            self._zoom = 20
        else:
            self.scale(factor, factor)

    def mouseDoubleClickEvent(self, event: QMouseEvent):
        if not self._empty:
            self.reset_view()

class ImageViewerDialog(QDialog):
    def __init__(self, image_path: str, parent=None, navigator: Optional[ImageNavigator] = None):
        super().__init__(parent)
        self.setWindowTitle("Image Viewer")
        
        # Use provided navigator or create a folder-based navigator as fallback
        self.navigator = navigator if navigator else FolderBasedNavigator(image_path)
        
        # Create main layout with just the viewer
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        # Create viewer
        self.viewer = ImageViewerWidget()
        main_layout.addWidget(self.viewer)
        
        # Create overlay navigation buttons
        self.prev_button = QPushButton("◀", self)
        self.prev_button.clicked.connect(self.go_to_previous)
        self.prev_button.setFixedSize(60, 80)
        self.prev_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(0, 0, 0, 100);
                color: white;
                border: 2px solid rgba(255, 255, 255, 100);
                border-radius: 8px;
                font-size: 20px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: rgba(0, 0, 0, 150);
                border: 2px solid rgba(255, 255, 255, 200);
                font-size: 22px;
            }
            QPushButton:pressed {
                background-color: rgba(0, 0, 0, 200);
            }
            QPushButton:disabled {
                background-color: rgba(0, 0, 0, 50);
                color: rgba(255, 255, 255, 100);
                border: 2px solid rgba(255, 255, 255, 50);
            }
        """)
        
        self.next_button = QPushButton("▶", self)
        self.next_button.clicked.connect(self.go_to_next)
        self.next_button.setFixedSize(60, 80)
        self.next_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(0, 0, 0, 100);
                color: white;
                border: 2px solid rgba(255, 255, 255, 100);
                border-radius: 8px;
                font-size: 20px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: rgba(0, 0, 0, 150);
                border: 2px solid rgba(255, 255, 255, 200);
                font-size: 22px;
            }
            QPushButton:pressed {
                background-color: rgba(0, 0, 0, 200);
            }
            QPushButton:disabled {
                background-color: rgba(0, 0, 0, 50);
                color: rgba(255, 255, 255, 100);
                border: 2px solid rgba(255, 255, 255, 50);
            }
        """)
        
        # Create info label overlay (top center)
        self.image_info_label = QLabel(self)
        self.image_info_label.setAlignment(Qt.AlignCenter)
        self.image_info_label.setStyleSheet("""
            QLabel {
                background-color: rgba(0, 0, 0, 120);
                color: white;
                border-radius: 8px;
                padding: 8px 16px;
                font-weight: bold;
                font-size: 12px;
            }
        """)
        
        # Auto-hide timer for buttons and info label
        self.hide_timer = QTimer()
        self.hide_timer.timeout.connect(self.hide_overlays)
        self.hide_timer.setSingleShot(True)
        
        # Track mouse movement to show/hide overlays
        self.setMouseTracking(True)
        self.viewer.setMouseTracking(True)
        
        # Set up keyboard shortcuts
        self.prev_shortcut = QShortcut(QKeySequence(Qt.Key_Left), self)
        self.prev_shortcut.activated.connect(self.go_to_previous)
        
        self.next_shortcut = QShortcut(QKeySequence(Qt.Key_Right), self)
        self.next_shortcut.activated.connect(self.go_to_next)
        
        self.close_shortcut = QShortcut(QKeySequence(Qt.Key_Escape), self)
        self.close_shortcut.activated.connect(self.close)
        
        # Load the initial image
        self.load_current_image()
        
        self.resize(1000, 700)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        
        # Position overlays after initial setup
        QTimer.singleShot(50, self.position_overlays)
        
        # Initially hide navigation buttons (they'll show on mouse movement)
        self.prev_button.hide()
        self.next_button.hide()
    
    def load_current_image(self):
        """Load the current image and update the info label."""
        current_path = self.navigator.get_current_image()
        if current_path:
            self.viewer.set_image(current_path)
            
            # Update window title and info label
            filename = os.path.basename(current_path)
            self.setWindowTitle(f"Image Viewer - {filename}")
            
            current_index, total_count = self.navigator.get_navigation_info()
            if self.navigator.has_navigation():
                self.image_info_label.setText(f"{current_index + 1} of {total_count} - {filename}")
            else:
                self.image_info_label.setText(filename)
            
            # Update button states
            self.prev_button.setEnabled(self.navigator.get_previous_image() is not None)
            self.next_button.setEnabled(self.navigator.get_next_image() is not None)
            
            # Show/hide navigation buttons if no navigation is available
            nav_enabled = self.navigator.has_navigation()
            self.prev_button.setVisible(nav_enabled)
            self.next_button.setVisible(nav_enabled)
            
            # Adjust info label size to content
            self.image_info_label.adjustSize()
            self.position_overlays()
    
    def position_overlays(self):
        """Position the overlay buttons and info label."""
        # Get dialog dimensions
        dialog_width = self.width()
        dialog_height = self.height()
        
        # Position previous button (left center)
        prev_x = 20
        prev_y = (dialog_height - self.prev_button.height()) // 2
        self.prev_button.move(prev_x, prev_y)
        
        # Position next button (right center)
        next_x = dialog_width - self.next_button.width() - 20
        next_y = (dialog_height - self.next_button.height()) // 2
        self.next_button.move(next_x, next_y)
        
        # Position info label (top center)
        info_x = (dialog_width - self.image_info_label.width()) // 2
        info_y = 20
        self.image_info_label.move(info_x, info_y)
    
    def resizeEvent(self, event):
        """Handle window resize to reposition overlays."""
        super().resizeEvent(event)
        self.position_overlays()
    
    def mouseMoveEvent(self, event):
        """Show overlays when mouse moves."""
        super().mouseMoveEvent(event)
        self.show_overlays()
    
    def show_overlays(self):
        """Show overlay buttons and info label."""
        if self.navigator.has_navigation():
            self.prev_button.show()
            self.next_button.show()
        self.image_info_label.show()
        
        # Reset the hide timer
        self.hide_timer.stop()
        self.hide_timer.start(3000)  # Hide after 3 seconds of no mouse movement
    
    def hide_overlays(self):
        """Hide overlay buttons and info label."""
        if self.navigator.has_navigation():
            self.prev_button.hide()
            self.next_button.hide()
        # Keep info label visible, just hide buttons
    
    def go_to_previous(self):
        """Navigate to the previous image."""
        if self.navigator.move_to_previous():
            self.load_current_image()
            self.show_overlays()  # Show overlays when navigating
    
    def go_to_next(self):
        """Navigate to the next image."""
        if self.navigator.move_to_next():
            self.load_current_image()
            self.show_overlays()  # Show overlays when navigating

    @staticmethod
    def create_from_folder(image_path, parent=None):
        """Create an ImageViewerDialog with folder-based navigation."""
        navigator = FolderBasedNavigator(image_path)
        return ImageViewerDialog(image_path, parent, navigator)
