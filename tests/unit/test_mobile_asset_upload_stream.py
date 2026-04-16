import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.asset_upload_stream import TransferAssetUploadStream


class TestTransferAssetUploadStream(unittest.TestCase):
    def test_allows_parallel_request_ids_when_chunks_are_addressed_explicitly(self):
        stream = TransferAssetUploadStream()
        stream.start(request_id="req-1", metadata_payload={"asset_id": "asset-1"})
        stream.start(request_id="req-2", metadata_payload={"asset_id": "asset-2"})

        self.assertIsNone(stream.append_chunk(chunk=b"abc", request_id="req-1"))
        self.assertIsNone(stream.append_chunk(chunk=b"defg", request_id="req-2"))

        payload_one = stream.complete(request_id="req-1")
        payload_two = stream.complete(request_id="req-2")
        self.assertEqual(payload_one.content_length, 3)
        self.assertEqual(payload_two.content_length, 4)
        self.assertEqual(payload_one.metadata_payload["asset_id"], "asset-1")
        self.assertEqual(payload_two.metadata_payload["asset_id"], "asset-2")
        Path(payload_one.temp_file_path).unlink(missing_ok=True)
        Path(payload_two.temp_file_path).unlink(missing_ok=True)

    def test_append_without_request_id_rejects_when_multiple_pending_streams_exist(self):
        stream = TransferAssetUploadStream()
        stream.start(request_id="req-1", metadata_payload={"asset_id": "asset-1"})
        stream.start(request_id="req-2", metadata_payload={"asset_id": "asset-2"})
        stream.start(request_id="req-3", metadata_payload={"asset_id": "asset-3"})
        stream.append_chunk(chunk=b"z", request_id="req-3")
        active_payload = stream.complete(request_id="req-3")
        Path(active_payload.temp_file_path).unlink(missing_ok=True)

        append_error = stream.append_chunk(chunk=b"x")
        self.assertEqual(
            append_error,
            "Desktop rejected transfer asset stream chunk because request ids do not match the active binary stream.",
        )

        stream.clear()

    def test_exclusive_start_replaces_previous_pending_usb_stream(self):
        stream = TransferAssetUploadStream()
        stream.start(request_id="req-1", metadata_payload={"asset_id": "asset-1"}, exclusive=True)
        self.assertIsNone(stream.append_chunk(chunk=b"older"))

        stream.start(request_id="req-2", metadata_payload={"asset_id": "asset-2"}, exclusive=True)
        self.assertIsNone(stream.append_chunk(chunk=b"newer"))

        completed_payload = stream.complete(request_id="req-2")
        self.assertEqual(completed_payload.content_length, 5)
        Path(completed_payload.temp_file_path).unlink(missing_ok=True)
        self.assertEqual(
            stream.complete(request_id="req-1"),
            "Desktop did not receive transfer asset stream metadata before completion.",
        )


if __name__ == "__main__":
    unittest.main()
