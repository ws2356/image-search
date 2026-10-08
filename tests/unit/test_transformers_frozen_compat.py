# The transformers/PyInstaller compat shim guards the bundled model load:
# short frozen module paths must not crash the auto_docstring import-time
# path inspection.
import sys
import unittest
import unittest.mock

from dt_image_search.tools.transformers_frozen_compat import (
    install_transformers_pyinstaller_compat,
    is_transformers_models_module_path,
)


class IsModelsModulePathTests(unittest.TestCase):
    def test_deep_models_path_matches(self):
        path = "/app/transformers/models/xlm_roberta/modeling_xlm_roberta.py"
        self.assertTrue(is_transformers_models_module_path(path))

    def test_deep_non_models_path_does_not_match(self):
        path = "/app/transformers/modeling_layers.py"
        self.assertFalse(is_transformers_models_module_path(path))

    def test_short_frozen_path_does_not_match(self):
        # the crash case: no depth for [-3]
        self.assertFalse(is_transformers_models_module_path("transformers/modeling_layers.py"))

    def test_none_path_does_not_match(self):
        self.assertFalse(is_transformers_models_module_path(None))

    def test_packaged_module_path_matches_model_subdirs_only(self):
        # bundle-style short path under models/ is fine
        path = "/models/xlm_roberta/modeling_xlm_roberta.py"
        self.assertTrue(is_transformers_models_module_path(path))


class InstallTests(unittest.TestCase):
    def setUp(self):
        import importlib
        self.auto_docstring = importlib.import_module("transformers.utils.auto_docstring")
        self._original = self.auto_docstring.get_model_name

    def tearDown(self):
        self.auto_docstring.get_model_name = self._original

    def test_noop_when_not_frozen(self):
        install_transformers_pyinstaller_compat()
        self.assertIs(self.auto_docstring.get_model_name, self._original)

    def test_installs_guard_when_frozen_and_is_idempotent(self):
        with unittest.mock.patch.object(sys, "frozen", True, create=True):
            install_transformers_pyinstaller_compat()
            wrapped = self.auto_docstring.get_model_name
            self.assertIsNot(wrapped, self._original)
            self.assertTrue(getattr(wrapped, "_frozen_compat_installed", False))

            # second call must be a no-op (no wrapper-of-wrapper)
            install_transformers_pyinstaller_compat()
            self.assertIs(self.auto_docstring.get_model_name, wrapped)

    def test_frozen_guard_names_no_model_for_short_paths(self):
        def _dummy_func():
            pass

        with unittest.mock.patch.object(sys, "frozen", True, create=True):
            install_transformers_pyinstaller_compat()
            wrapped = self.auto_docstring.get_model_name

            with unittest.mock.patch("inspect.getsourcefile", return_value="transformers/modeling_layers.py"):
                self.assertIsNone(wrapped(_dummy_func))

            with unittest.mock.patch(
                "inspect.getsourcefile",
                return_value="/app/transformers/models/xlm_roberta/modeling_xlm_roberta.py",
            ):
                self.assertEqual(wrapped(_dummy_func), "xlm_roberta")


if __name__ == "__main__":
    unittest.main()
