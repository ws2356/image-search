import threading

class EventBus:
    def __init__(self):
        self._subscribers = {}
        self._lock = threading.RLock()

    def subscribe(self, event_name, callback):
        """Subscribe to an event and return a disposable for unsubscribing."""
        with self._lock:
            self._subscribers.setdefault(event_name, []).append(callback)

        class _Subscription:
            def __init__(self, bus, event, cb):
                self._bus = bus
                self._event = event
                self._cb = cb
                self._disposed = False
                self._lock = bus._lock  # reuse the same lock

            def dispose(self):
                with self._lock:
                    if not self._disposed:
                        callbacks = self._bus._subscribers.get(self._event, [])
                        if self._cb in callbacks:
                            callbacks.remove(self._cb)
                        if not callbacks:
                            self._bus._subscribers.pop(self._event, None)
                        self._disposed = True

        return _Subscription(self, event_name, callback)

    def publish(self, event_name, *args, **kwargs):
        """Notify all subscribers of an event (thread-safe)."""
        with self._lock:
            # Copy to avoid mutation during iteration
            callbacks = list(self._subscribers.get(event_name, []))

        # Execute callbacks outside the lock
        for callback in callbacks:
            try:
                callback(*args, **kwargs)
            except Exception as e:
                # Log or handle callback exceptions safely
                print(f"Error in event handler for '{event_name}': {e}")

default_bus = EventBus()
