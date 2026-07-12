"""Unit tests for SessionIdGenerator."""

import unittest
import tempfile
from pathlib import Path

from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator


class TestSessionIdGenerator(unittest.TestCase):
    def setUp(self):
        self._tmp_dir = tempfile.mkdtemp()
        self._counter_file = Path(self._tmp_dir) / "session_id_counter.txt"

    def _make_gen(self) -> SessionIdGenerator:
        return SessionIdGenerator(counter_file=self._counter_file)

    def test_first_id_is_1(self):
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")

    def test_ids_increment_monotonically(self):
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")
        self.assertEqual(gen.next_session_id(), "2")
        self.assertEqual(gen.next_session_id(), "3")

    def test_hex_format_no_leading_zero(self):
        gen = self._make_gen()
        for _ in range(9):
            gen.next_session_id()
        # 10th call -> value=10 -> hex is "a"
        self.assertEqual(gen.next_session_id(), "a")

    def test_last_id_is_ff(self):
        gen = self._make_gen()
        for _ in range(254):
            gen.next_session_id()
        # 255th call -> value=255 -> hex is "ff"
        self.assertEqual(gen.next_session_id(), "ff")

    def test_wrap_around_after_ff(self):
        gen = self._make_gen()
        for _ in range(255):
            gen.next_session_id()
        # 256th call -> wraps to 1
        self.assertEqual(gen.next_session_id(), "1")

    def test_persistence_across_instances(self):
        gen1 = self._make_gen()
        gen1.next_session_id()  # "1"
        gen1.next_session_id()  # "2"
        gen2 = self._make_gen()
        self.assertEqual(gen2.next_session_id(), "3")

    def test_persistence_wrap_around(self):
        self._counter_file.write_text("255")
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")


if __name__ == "__main__":
    unittest.main()
