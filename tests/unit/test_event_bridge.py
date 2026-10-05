# Unit tests for the bus→WebSocket event bridge.
import sys
import unittest
from unittest.mock import MagicMock

noop_decorator = lambda f: f

# dts_index import chain stubs (search_service transitively imported by routes)
sys.modules['faiss'] = MagicMock()
sys.modules['open_clip'] = MagicMock()
sys.modules['torch'] = MagicMock()
sys.modules['torchvision'] = MagicMock()
sys.modules['torchvision.transforms'] = MagicMock()
sys.modules['hf_xet'] = MagicMock()
sys.modules['requests'] = MagicMock()
sys.modules['psutil'] = MagicMock()
sys.modules['watchdog'] = MagicMock()
sys.modules['watchdog.observers'] = MagicMock()
sys.modules['watchdog.events'] = MagicMock()
sys.modules['opentelemetry'] = MagicMock()
sys.modules['opentelemetry.trace'] = MagicMock()
sys.modules['opentelemetry.sdk'] = MagicMock()
sys.modules['opentelemetry.sdk.trace'] = MagicMock()
sys.modules['opentelemetry.sdk.trace.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.trace_exporter'] = MagicMock()
sys.modules['opentelemetry.sdk.resources'] = MagicMock()
sys.modules['opentelemetry.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.metric_exporter'] = MagicMock()
sys.modules['opentelemetry._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http._log_exporter'] = MagicMock()
sys.modules['opentelemetry.instrumentation'] = MagicMock()
sys.modules['opentelemetry.context'] = MagicMock()
sys.modules['opentelemetry.context.contextvars_context'] = MagicMock()
sys.modules['pc_common.telemetry.telemetry_client'] = MagicMock()
mock_perf = MagicMock()
mock_perf.perffunc = noop_decorator
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf
sys.modules['pc_common.telemetry.telemetry_client'].with_trace = lambda _: noop_decorator

import unittest
from unittest.mock import MagicMock

from dt_image_search.index_server.event_bridge import EVENT_NAMES, attach_event_bridge


class RecordingBroker:
    def __init__(self):
        self.payloads = []

    def broadcast_threadsafe(self, payload):
        self.payloads.append(payload)


class TestEventBridge(unittest.TestCase):
    def setUp(self):
        # isolate the shared bus
        import dt_image_search.tools.dts_event_bus as bus_module
        self._orig = dict(bus_module.default_bus._subscribers)
        bus_module.default_bus._subscribers = {}

    def tearDown(self):
        import dt_image_search.tools.dts_event_bus as bus_module
        bus_module.default_bus._subscribers = self._orig

    def test_event_names_pinned(self):
        self.assertEqual(EVENT_NAMES, ("status_message", "fs_changed", "folder_deleted_from_ui", "model_load_failed"))

    def test_publishes_forwarded_with_envelope(self):
        from dt_image_search.tools.dts_event_bus import default_bus
        broker = RecordingBroker()
        disposable = attach_event_bridge(broker)

        default_bus.publish("status_message", message="indexing 1/2")

        self.assertEqual(broker.payloads, [{"event": "status_message", "data": {"message": "indexing 1/2"}}])
        disposable.dispose()

    def test_non_whitelisted_event_not_forwarded(self):
        from dt_image_search.tools.dts_event_bus import default_bus
        broker = RecordingBroker()
        attach_event_bridge(broker)

        default_bus.publish("is.network.ip_changed", old_ips=[], new_ips=[])

        self.assertEqual(broker.payloads, [])

    def test_dispose_stops_forwarding(self):
        from dt_image_search.tools.dts_event_bus import default_bus
        broker = RecordingBroker()
        disposable = attach_event_bridge(broker)
        disposable.dispose()

        default_bus.publish("status_message", message="later")

        self.assertEqual(broker.payloads, [])

    def test_watchdog_event_sanitized_to_summary(self):
        from dt_image_search.tools.dts_event_bus import default_bus

        class FakeWrappedEvent:
            pass

        event = MagicMock(spec=object)
        event.src_path = "/photos/new.jpg"
        type_name = type(event).__name__

        broker = RecordingBroker()
        attach_event_bridge(broker)

        default_bus.publish("fs_changed", event=event)

        data = broker.payloads[0]["data"]
        self.assertEqual(data["event"]["type"], type_name)
        self.assertEqual(data["event"]["src_path"], "/photos/new.jpg")
        # must be JSON-serializable
        import json
        json.dumps(broker.payloads[0])


class TestWsIntegration(unittest.TestCase):
    def setUp(self):
        import dt_image_search.tools.dts_event_bus as bus_module
        self._orig = dict(bus_module.default_bus._subscribers)
        bus_module.default_bus._subscribers = {}

    def tearDown(self):
        import dt_image_search.tools.dts_event_bus as bus_module
        bus_module.default_bus._subscribers = self._orig

    def test_status_message_reaches_ws_client(self):
        from dt_image_search.tools import status_messenger
        from dt_image_search.index_server.app import create_app
        from fastapi.testclient import TestClient

        app = create_app(ctx=None, token="tok")
        with TestClient(app) as client:
            with client.websocket_connect("/events?auth=tok") as ws:
                status_messenger.show("via integration")
                data = ws.receive_json()
        self.assertEqual(data, {"event": "status_message", "data": {"message": "via integration"}})

    def test_ws_connects_even_when_static_dir_is_mounted(self):
        # Regression: the catch-all SPA mount used to swallow the WS handshake
        # whenever a static dir was set (i.e. always in production).
        import os
        import tempfile
        from dt_image_search.tools import status_messenger
        from dt_image_search.index_server.app import create_app
        from fastapi.testclient import TestClient

        with tempfile.TemporaryDirectory() as temp_dir:
            with open(os.path.join(temp_dir, "index.html"), "w") as f:
                f.write("<html></html>")
            app = create_app(ctx=None, token="tok", static_dir=temp_dir)
            with TestClient(app) as client:
                with client.websocket_connect("/events?auth=tok") as ws:
                    status_messenger.show("with static")
                    data = ws.receive_json()
        self.assertEqual(data["data"]["message"], "with static")

    def test_spa_entry_is_token_gated(self):
        import os
        import tempfile
        from dt_image_search.index_server.app import create_app
        from fastapi.testclient import TestClient

        with tempfile.TemporaryDirectory() as temp_dir:
            with open(os.path.join(temp_dir, "index.html"), "w") as f:
                f.write("<html>app</html>")
            app = create_app(ctx=None, token="tok", static_dir=temp_dir)
            client = TestClient(app)
            self.assertEqual(client.get("/").status_code, 401)
            self.assertEqual(client.get("/some/spa/route").status_code, 401)
            ok = client.get("/", params={"auth": "tok"})
            self.assertEqual(ok.status_code, 200)

    def test_ws_with_invalid_token_is_rejected(self):
        from dt_image_search.index_server.app import create_app
        from fastapi.testclient import TestClient
        from starlette.websockets import WebSocketDisconnect

        app = create_app(ctx=None, token="tok")
        with TestClient(app) as client:
            with self.assertRaises(WebSocketDisconnect):
                with client.websocket_connect("/events?auth=bad"):
                    pass


if __name__ == "__main__":
    unittest.main()
