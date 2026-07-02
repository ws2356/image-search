import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.contracts import DownloadedImagePayload, DownloadedTextPayload, InstantShareMetadata
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.contracts import PayloadClass, TargetIntent, TrustMode


class _ClipboardRecorder:
    def __init__(self):
        self.texts = []
        self.images = []

    def write_text(self, text: str) -> None:
        self.texts.append(text)

    def write_image_bytes(self, image_bytes: bytes) -> None:
        self.images.append(image_bytes)


def _text_metadata():
    return InstantShareMetadata(
        payload_class=PayloadClass.TEXT,
        target_intent=TargetIntent.CLIPBOARD_ONLY,
        trust_mode=TrustMode.FIRST_SHARE,
    )


def _image_metadata():
    return InstantShareMetadata(
        payload_class=PayloadClass.IMAGE,
        target_intent=TargetIntent.CLIPBOARD_OR_FILE,
        trust_mode=TrustMode.TRUSTED_DIRECT,
    )


class TestInstantShareDeliveryService(unittest.TestCase):
    def test_text_delivery_writes_clipboard(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)

        result = delivery_service.deliver_text(
            DownloadedTextPayload(metadata=_text_metadata(), text_utf8="copied text")
        )

        self.assertEqual(clipboard.texts, ["copied text"])
        self.assertEqual(result.target_result.clipboard_written, True)

    def test_image_delivery_writes_clipboard_when_mode_is_clipboard(self):
        clipboard = _ClipboardRecorder()
        delivery_service = InstantShareDeliveryService(
            clipboard_writer=clipboard,
            image_delivery_mode="clipboard",
        )

        result = delivery_service.deliver_image(
            DownloadedImagePayload(
                metadata=_image_metadata(),
                image_bytes=b"image-bits",
                filename="share.png",
                content_type="image/png",
            )
        )

        self.assertEqual(clipboard.images, [b"image-bits"])
        self.assertEqual(result.target_result.clipboard_written, True)

    def test_image_delivery_defaults_to_downloads_folder_and_resolves_collision(self):
        clipboard = _ClipboardRecorder()
        with tempfile.TemporaryDirectory() as temp_dir:
            fake_home = Path(temp_dir)
            delivery_service = InstantShareDeliveryService(clipboard_writer=clipboard)

            with patch("dt_image_search.instant_sharing.delivery.Path.home", return_value=fake_home):
                first_result = delivery_service.deliver_image(
                    DownloadedImagePayload(
                        metadata=_image_metadata(),
                        image_bytes=b"first-image",
                        filename="share.png",
                        content_type="image/png",
                    )
                )
                second_result = delivery_service.deliver_image(
                    DownloadedImagePayload(
                        metadata=_image_metadata(),
                        image_bytes=b"second-image",
                        filename="share.png",
                        content_type="image/png",
                    )
                )

            downloads_dir = (fake_home / "Downloads").resolve()
            self.assertTrue((downloads_dir / "share.png").exists())
            self.assertTrue((downloads_dir / "share-2.png").exists())
            self.assertEqual(first_result.target_result.output_paths[0], (downloads_dir / "share.png").as_posix())
            self.assertEqual(second_result.target_result.output_paths[0], (downloads_dir / "share-2.png").as_posix())

    def test_image_delivery_rejects_unsafe_filename(self):
        delivery_service = InstantShareDeliveryService(downloads_dir=Path("/tmp"))

        with self.assertRaises(InstantShareError) as exc_info:
            delivery_service.deliver_image(
                DownloadedImagePayload(
                    metadata=_image_metadata(),
                    image_bytes=b"image-bits",
                    filename="../escape.png",
                    content_type="image/png",
                )
            )

        self.assertEqual(exc_info.exception.error_code.value, "DELIVERY_PATH_INVALID")


if __name__ == "__main__":
    unittest.main()