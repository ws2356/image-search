# Bus → WebSocket event bridge: forwards the whitelisted dts_event_bus events
# to every connected web UI client as {"event": ..., "data": {...}} envelopes.
from dt_image_search.tools.dts_event_bus import default_bus

EVENT_NAMES = ("status_message", "fs_changed", "folder_deleted_from_ui", "model_load_failed")


def _sanitize(value):
    """Make bus payloads JSON-serializable; watchdog event objects become
    {type, src_path} summaries."""
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    try:
        import json
        json.dumps(value)
        return value
    except (TypeError, ValueError):
        pass
    return {
        "type": type(value).__name__,
        "src_path": str(getattr(value, "src_path", value)),
    }


def attach_event_bridge(broker):
    """Subscribe the broker to the whitelisted bus events.
    Returns a disposable: .dispose() unsubscribes everything."""
    subscriptions = []

    def make_callback(event_name):
        def callback(**kwargs):
            data = {k: _sanitize(v) for k, v in kwargs.items()}
            broker.broadcast_threadsafe({"event": event_name, "data": data})
        return callback

    for name in EVENT_NAMES:
        subscriptions.append(default_bus.subscribe(name, make_callback(name)))

    class _Disposable:
        def dispose(self):
            for sub in subscriptions:
                sub.dispose()

    return _Disposable()
