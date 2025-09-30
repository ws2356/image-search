from PySide6.QtCore import Qt, QObject, QEvent

class DTSEscClearEventFilter(QObject):
    def eventFilter(self, obj, event):
        if event.type() == QEvent.KeyPress and event.key() == Qt.Key_Escape:
            obj.clear()
            return True
        return False
