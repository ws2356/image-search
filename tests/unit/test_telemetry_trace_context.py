import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
_original_pytest_marker = os.environ.get("PYTEST_CURRENT_TEST")
os.environ["PYTEST_CURRENT_TEST"] = "tests.unit.test_telemetry_trace_context"

from dt_image_search.telemetry.telemetry_client import add_span

if _original_pytest_marker is None:
    os.environ.pop("PYTEST_CURRENT_TEST", None)
else:
    os.environ["PYTEST_CURRENT_TEST"] = _original_pytest_marker


class TestTelemetryTraceContext(unittest.TestCase):
    def test_add_span_uses_remote_traceparent_when_present(self):
        remote_traceparent = "00-ff000000000000000000000000000041-ff00000000000041-01"

        with add_span(
            "mobile.desktop.transfer.start",
            carrier={"traceparent": remote_traceparent},
        ) as span:
            trace_id = f"{span.context.trace_id:032x}"
            parent_span_id = f"{span.parent.span_id:016x}"

        self.assertEqual(trace_id, "ff000000000000000000000000000041")
        self.assertEqual(parent_span_id, "ff00000000000041")


if __name__ == "__main__":
    unittest.main()
