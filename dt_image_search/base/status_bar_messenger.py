# status_messenger.py
from PySide6.QtCore import QObject, Signal

class StatusBarMessenger(QObject):
    show_status_message = Signal(str)

status_bar_messenger = StatusBarMessenger()