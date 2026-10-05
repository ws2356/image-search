# Unit tests for the Qt-free status messenger.
# status_messenger is built on dts_event_bus.default_bus so that the web
# EventBridge and the Qt bridge observe the same status message stream.
import unittest
from unittest.mock import MagicMock

from dt_image_search.tools import status_messenger
from dt_image_search.tools.dts_event_bus import default_bus


class TestStatusMessenger(unittest.TestCase):
    def setUp(self):
        # Isolate from other tests' subscriptions on the shared bus.
        self._orig = default_bus._subscribers.pop(status_messenger._EVENT, None)

    def tearDown(self):
        default_bus._subscribers.pop(status_messenger._EVENT, None)
        if self._orig is not None:
            default_bus._subscribers[status_messenger._EVENT] = self._orig

    def test_show_calls_all_subscribers_in_order(self):
        calls = []
        d1 = status_messenger.subscribe(lambda m: calls.append(("a", m)))
        d2 = status_messenger.subscribe(lambda m: calls.append(("b", m)))

        status_messenger.show("indexing folder 1/2")

        self.assertEqual(calls, [("a", "indexing folder 1/2"), ("b", "indexing folder 1/2")])
        d1.dispose()
        d2.dispose()

    def test_dispose_stops_receiving(self):
        received = []
        d = status_messenger.subscribe(received.append)

        d.dispose()
        status_messenger.show("after dispose")

        self.assertEqual(received, [])

    def test_subscriber_exception_does_not_break_others(self):
        bad = MagicMock(side_effect=RuntimeError("boom"))
        good = MagicMock()
        status_messenger.subscribe(bad)
        status_messenger.subscribe(good)

        status_messenger.show("msg")

        good.assert_called_once_with("msg")

    def test_publishes_on_default_bus_with_canonical_event_name(self):
        seen = {}
        d = default_bus.subscribe(status_messenger._EVENT, lambda **kw: seen.update(kw))

        status_messenger.show("via bus")

        self.assertEqual(seen, {"message": "via bus"})
        d.dispose()


if __name__ == "__main__":
    unittest.main()
