"""Indexing must stop when model load fails."""
import unittest
from dt_image_search.index import dts_index
from dt_image_search.index.dts_index import MODEL_STATE_FAILED


class IndexModelFailureTests(unittest.TestCase):
    def test_add_to_index_refuses_to_submit_when_model_is_not_ready(self):
        """Index submission is suppressed on model load failure."""
        with unittest.mock.patch.object(dts_index, "_model_state", MODEL_STATE_FAILED):
            self.assertFalse(dts_index._add_to_index(None, "/tmp/index.faiss", 123, []))
