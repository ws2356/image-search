import time
import typing
import threading

class ThrottledCallback:
    def __init__(self, callback: typing.Callable, throttle_interval: float = 0.5):
        self.callback = callback
        self.throttle_interval = throttle_interval
        self._last_emit_time = 0.0
        self._pending_args = None
        self._pending_kwargs = None
        self._timer = None
        self._lock = threading.Lock()
    
    def __call__(self, *args, **kwargs):
        current_time = time.time()
        with self._lock:
            if current_time - self._last_emit_time >= self.throttle_interval:
                # Emit immediately
                self.callback(*args, **kwargs)
                self._last_emit_time = current_time
                # Cancel any pending timer
                if self._timer is not None:
                    self._timer.cancel()
                    self._timer = None
                self._pending_args = None
                self._pending_kwargs = None
            else:
                # Store the latest call and schedule it for later
                self._pending_args = args
                self._pending_kwargs = kwargs
                
                # Cancel existing timer if any
                if self._timer is not None:
                    self._timer.cancel()
                
                # Schedule a deferred call
                time_until_next = self.throttle_interval - (current_time - self._last_emit_time)
                self._timer = threading.Timer(time_until_next, self._emit_pending)
                self._timer.daemon = True
                self._timer.start()
    
    def _emit_pending(self):
        with self._lock:
            if self._pending_args is not None:
                self.callback(*self._pending_args, **self._pending_kwargs)
                self._last_emit_time = time.time()
                self._pending_args = None
                self._pending_kwargs = None
            self._timer = None