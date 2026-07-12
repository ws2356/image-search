"""Test that InstantShareHeaders accepts short hex session IDs."""

import unittest
from dt_image_search.instant_sharing.contracts import InstantShareHeaders


class TestInstantShareHeadersShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="a",
            device_id="dev1",
        )
        # Should not raise
        headers.validate(requires_signature=False)

    def test_validate_accepts_ff_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="ff",
            device_id="dev1",
        )
        headers.validate(requires_signature=False)

    def test_validate_rejects_empty_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="",
            device_id="dev1",
        )
        with self.assertRaises(ValueError):
            headers.validate(requires_signature=False)


if __name__ == "__main__":
    unittest.main()
