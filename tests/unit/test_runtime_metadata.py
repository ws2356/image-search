import os
import sys
import tempfile
import unittest
import warnings
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))


from dt_image_search.telemetry import runtime_metadata


class TestRuntimeMetadata(unittest.TestCase):
    @patch('dt_image_search.tools.dt_is_debug.is_debug', return_value=True)
    def test_resolve_package_type_debug(self, _mock_is_debug):
        self.assertEqual(runtime_metadata.resolve_package_type(), runtime_metadata.PACKAGE_TYPE_DEBUG)

    @patch('dt_image_search.tools.dt_is_debug.is_debug', return_value=True)
    def test_resolve_service_version_debug_is_empty(self, _mock_is_debug):
        self.assertEqual(runtime_metadata.resolve_service_version(), '')

    @unittest.skipIf(sys.platform != 'win32', 'Windows-only test: requires AppxManifest.xml')
    @patch('dt_image_search.tools.dt_is_debug.is_debug', return_value=False)
    def test_resolve_service_version_from_manifest(self, _mock_is_debug):
        with tempfile.TemporaryDirectory() as tmpdir:
            manifest_path = Path(tmpdir) / 'AppxManifest.xml'
            manifest_path.write_text(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">\n'
                '  <Identity Version="2.3.4.5" />\n'
                '</Package>\n',
                encoding='utf-8',
            )

            with patch.object(runtime_metadata, '_candidate_manifest_paths', return_value=[manifest_path]):
                self.assertEqual(runtime_metadata.resolve_service_version(), '2.3.4.5')

    @unittest.skipIf(sys.platform != 'win32', 'Windows-only test: requires AppxManifest.xml')
    @patch('dt_image_search.tools.dt_is_debug.is_debug', return_value=False)
    def test_resolve_service_version_returns_empty_on_parse_failure(self, _mock_is_debug):
        with tempfile.TemporaryDirectory() as tmpdir:
            manifest_path = Path(tmpdir) / 'AppxManifest.xml'
            manifest_path.write_text('<Package></Package>', encoding='utf-8')

            with patch.object(runtime_metadata, '_candidate_manifest_paths', return_value=[manifest_path]):
                with warnings.catch_warnings(record=True) as caught_warnings:
                    warnings.simplefilter('always')
                    self.assertEqual(runtime_metadata.resolve_service_version(), '')

            self.assertTrue(any('Failed to resolve service.version' in str(item.message) for item in caught_warnings))


if __name__ == '__main__':
    unittest.main()