from PySide6.QtCore import QObject, Signal, Qt

class MainThreadDispatcher(QObject):
    _dispatch = Signal(object, name="dispatch")  # payload is a callable

    def __init__(self):
        super().__init__()
        # ensure slot runs in this QObject’s thread (the main thread)
        self._dispatch.connect(self._on_dispatch, Qt.QueuedConnection)

    def _on_dispatch(self, fn):
        fn()

    def post(self, fn):
        """Call this from any thread."""
        self._dispatch.emit(fn)

dispatcher = MainThreadDispatcher()

# anywhere in your code (worker threads, etc.):
# dispatcher.post(lambda: window.label.setText("From worker → main"))
