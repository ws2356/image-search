import os
import sys
import unittest
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import MagicMock, patch


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
sys.modules["dt_image_search.telemetry.telemetry_client"] = MagicMock()

from dt_image_search import pil_image_support


class TestPILImageSupport(unittest.TestCase):
    def setUp(self):
        pil_image_support._HEIF_DECODER_ATTEMPTED = False
        pil_image_support._HEIF_DECODER_REGISTERED = False

    @patch("dt_image_search.pil_image_support.log")
    @patch("dt_image_search.pil_image_support.import_module")
    def test_ensure_heif_decoder_registers_once_when_package_available(self, mock_import_module, mock_log):
        register_heif_opener = MagicMock()
        mock_import_module.return_value = SimpleNamespace(register_heif_opener=register_heif_opener)

        pil_image_support._ensure_heif_decoder_registered()
        pil_image_support._ensure_heif_decoder_registered()

        register_heif_opener.assert_called_once_with()
        mock_log.assert_called_once_with(
            "info",
            "image_decode",
            "Registered pillow-heif HEIC/HEIF decoder support.",
            pil_image_support.__file__,
        )

    @patch("dt_image_search.pil_image_support.log")
    @patch("dt_image_search.pil_image_support.import_module", side_effect=ModuleNotFoundError("missing"))
    def test_ensure_heif_decoder_logs_warning_without_decoder_or_native_fallback(self, mock_import_module, mock_log):
        with patch.object(pil_image_support, "_SIPS_PATH", None):
            pil_image_support._ensure_heif_decoder_registered()

        mock_log.assert_called_once_with(
            "warning",
            "image_decode",
            "pillow-heif is unavailable and no native HEIC fallback exists on this platform.",
            pil_image_support.__file__,
        )

    @patch("dt_image_search.pil_image_support._ensure_heif_decoder_registered")
    @patch("dt_image_search.pil_image_support.Image.open")
    def test_open_pil_image_returns_copied_image(self, mock_image_open, mock_register):
        loaded_image = MagicMock()
        mock_image_open.return_value.__enter__.return_value = loaded_image

        with pil_image_support.open_pil_image("IMG_0001.HEIC") as image:
            self.assertIs(image, loaded_image)

        mock_register.assert_called_once_with()
        loaded_image.close.assert_not_called()

    @patch("dt_image_search.pil_image_support._open_heif_with_native_fallback")
    @patch("dt_image_search.pil_image_support._ensure_heif_decoder_registered")
    @patch("dt_image_search.pil_image_support.Image.open", side_effect=OSError("decode failed"))
    def test_open_pil_image_falls_back_for_heif_decode_errors(self, mock_image_open, mock_register, mock_native_fallback):
        fallback_image = MagicMock()

        @contextmanager
        def fallback_context():
            yield fallback_image

        mock_native_fallback.return_value = fallback_context()

        with pil_image_support.open_pil_image("IMG_0001.HEIC") as image:
            self.assertIs(image, fallback_image)

        mock_register.assert_called_once_with()
        mock_native_fallback.assert_called_once()
        fallback_image.close.assert_not_called()


if __name__ == "__main__":
    unittest.main()
