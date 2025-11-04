from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem,
    QDialog, QVBoxLayout, QSizePolicy
)
from PySide6.QtGui import QPixmap, QWheelEvent, QMouseEvent
from PySide6.QtCore import Qt, QPointF

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
    def __init__(self, image_path, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Image Viewer")
        self.viewer = ImageViewerWidget()
        self.viewer.set_image(image_path)

        layout = QVBoxLayout(self)
        layout.addWidget(self.viewer)

        self.resize(1000, 700)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
