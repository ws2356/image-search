# Status message fan-out for user-facing progress/status text.
# Built on dts_event_bus.default_bus with the canonical event name "status_message"
# so both the web EventBridge (WebSocket) and the legacy Qt bridge observe the
# same stream through a single channel.
from typing import Callable

from dt_image_search.tools.dts_event_bus import default_bus

_EVENT = "status_message"


class _Disposable:
    def __init__(self, subscription):
        self._subscription = subscription

    def dispose(self):
        self._subscription.dispose()


def subscribe(callback: Callable[[str], None]) -> _Disposable:
    """Subscribe to status messages; returns a disposable to unsubscribe."""
    subscription = default_bus.subscribe(_EVENT, lambda **kw: callback(kw["message"]))
    return _Disposable(subscription)


def show(message: str) -> None:
    """Publish a status message to all subscribers (thread-safe)."""
    default_bus.publish(_EVENT, message=message)
