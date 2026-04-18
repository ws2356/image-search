import logging
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
_original_pytest_marker = os.environ.get("PYTEST_CURRENT_TEST")
os.environ["PYTEST_CURRENT_TEST"] = "tests.unit.test_otel_attribute_sanitizer"

from dt_image_search.telemetry.telemetry_client import OtelAttributeSanitizerFilter

if _original_pytest_marker is None:
    os.environ.pop("PYTEST_CURRENT_TEST", None)
else:
    os.environ["PYTEST_CURRENT_TEST"] = _original_pytest_marker


class _ClientConnection:
    pass


def _make_record(**extras: object) -> logging.LogRecord:
    return logging.makeLogRecord(
        {
            "name": "telemetry-test",
            "msg": "test message",
            "levelno": logging.INFO,
            "levelname": "INFO",
            **extras,
        }
    )


class TestOtelAttributeSanitizerFilter(unittest.TestCase):
    def setUp(self):
        self._filter = OtelAttributeSanitizerFilter()

    def test_non_primitive_extra_is_stringified(self):
        record = _make_record(websocket=_ClientConnection())

        accepted = self._filter.filter(record)

        self.assertTrue(accepted)
        self.assertIsInstance(record.__dict__["websocket"], str)
        self.assertIn("_ClientConnection", record.__dict__["websocket"])

    def test_homogeneous_primitive_sequence_is_preserved(self):
        record = _make_record(chunk_sizes=[1, 2, 3])

        accepted = self._filter.filter(record)

        self.assertTrue(accepted)
        self.assertEqual(record.__dict__["chunk_sizes"], [1, 2, 3])

    def test_mixed_sequence_is_stringified(self):
        record = _make_record(metadata=[1, "two"])

        accepted = self._filter.filter(record)

        self.assertTrue(accepted)
        self.assertIsInstance(record.__dict__["metadata"], str)
        self.assertIn("[1, 'two']", record.__dict__["metadata"])

    def test_mapping_extra_is_stringified(self):
        record = _make_record(context={"id": "abc"})

        accepted = self._filter.filter(record)

        self.assertTrue(accepted)
        self.assertIsInstance(record.__dict__["context"], str)
        self.assertIn("{'id': 'abc'}", record.__dict__["context"])


if __name__ == "__main__":
    unittest.main()
