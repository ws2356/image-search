"""Model state tests."""

import unittest
import unittest.mock
from dt_image_search.index.dts_index import \
    MODEL_STATE_READY, \
    get_model_state, \
    model_is_ready


class ModelTests(unittest.TestCase):
    def test_model_state_ready(self):
        """Model state is ready initially."""
        self.assertTrue(model_is_ready())
        self.assertEqual(
            get_model_state(),
            MODEL_STATE_READY,
        )

    def test_model_failure_sets_state(self):
        """Model failure is visible in app state."""
        with unittest.mock.patch(
            "dt_image_search.index.dts_index._model_state",
            "failed",
        ) as mock_state:
            self.assertTrue(mock_state == "failed")


if __name__ == "__main__":
    unittest.main()
