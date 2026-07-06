"""Unit tests for WebRTCPeer protocol handling."""

import struct
import unittest
from unittest.mock import MagicMock, patch
from uuid import uuid4

from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler, StashEntry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry, TrustFlowType
from dt_image_search.instant_sharing.webrtc_peer import (
    WebRTCPeer,
    _encode_control,
    _read_control_message,
    _estimate_chunk_count,
    CHUNK_HEADER_FMT,
    CONTROL_TERMINATOR,
    MAX_MESSAGE_SIZE,
)

SID = str(uuid4())
STASH_ID = str(uuid4())
OPT = "123456"


def _make_stash() -> StashEntry:
    return StashEntry(
        stash_id=STASH_ID,
        content_type="text/plain",
        content="hello",
        files=[],
        opt_code=OPT,
        created_at=0.0,
        expires_at=99999.0,
    )


class TestWebRTCPeerMessages(unittest.TestCase):
    def setUp(self):
        self.qr_handler = MagicMock(spec=QRTriggerHandler)
        self._key_resolver_patcher = patch(
            "dt_image_search.instant_sharing.trust_server.X25519TrustSessionKeyResolver",
        )
        self._key_resolver_patcher.start()
        self.ts_reg = TrustSessionRegistry()
        self.ts_reg.create_session(
            session_id=SID,
            correlation_id=SID,
            flow_type=TrustFlowType.PC_TO_MOBILE,
            opt_code=OPT,
            stash_id=STASH_ID,
        )
        self.loop = MagicMock()
        self.peer: WebRTCPeer = WebRTCPeer(
            session_id=SID,
            stash=_make_stash(),
            qr_handler=self.qr_handler,
            trust_session_registry=self.ts_reg,
            loop=self.loop,
            relay_url="ws://mock.relay",
        )
        self.mock_dc = MagicMock()
        self.mock_dc.readyState = "open"
        self.peer._dc = self.mock_dc
        self.peer._authenticated = False

    def tearDown(self):
        self._key_resolver_patcher.stop()

    def _send_ctrl(self, msg: dict) -> None:
        self.peer._on_dc_message(_encode_control(msg))

    def test_handle_auth_valid_opt(self):
        self._send_ctrl({"msg": "auth", "opt_code": OPT})
        self.assertTrue(self.peer._authenticated)
        self.mock_dc.send.assert_called()
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded["msg"], "auth_ok")

    def test_handle_auth_invalid_opt(self):
        self._send_ctrl({"msg": "auth", "opt_code": "000000"})
        self.assertFalse(self.peer._authenticated)
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded["msg"], "auth_error")

    def test_handle_manifest_before_auth_returns_error(self):
        self._send_ctrl({"msg": "manifest"})
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded.get("code"), "auth_required")

    def test_handle_manifest_after_auth(self):
        self.peer._authenticated = True
        self.qr_handler.retrieve_stash_content.return_value = {
            "_status": 200,
            "files": [
                {"index": 0, "type": "text", "content_type": "text/plain", "content": "hi"},
            ],
        }
        self._send_ctrl({"msg": "manifest"})
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded["msg"], "manifest")
        self.assertEqual(len(decoded["files"]), 1)

    def test_handle_manifest_stash_not_found(self):
        self.peer._authenticated = True
        self.qr_handler.retrieve_stash_content.return_value = {"_status": 404, "error": "Stash not found"}
        self._send_ctrl({"msg": "manifest"})
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded["msg"], "error")

    def test_handle_download_before_auth_returns_error(self):
        self._send_ctrl({"msg": "download", "index": 0})
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded.get("code"), "auth_required")

    def test_handle_download_file_not_found(self):
        self.peer._authenticated = True
        self.qr_handler.retrieve_stash_file.return_value = (404, b"", "", "")
        self._send_ctrl({"msg": "download", "index": 0})
        sent = self.mock_dc.send.call_args[0][0]
        decoded = _read_control_message(sent)
        self.assertEqual(decoded["msg"], "error")

    def test_handle_download_sends_binary_data(self):
        self.peer._authenticated = True
        content = b"x" * 100
        self.qr_handler.retrieve_stash_file.return_value = (200, content, "text/plain", "hello.txt")
        self._send_ctrl({"msg": "download", "index": 0})

        calls = [c for c in self.mock_dc.send.call_args_list]
        control_messages = []
        binary_messages = []
        for call in calls:
            data = call[0][0]
            if isinstance(data, str) and data.endswith(CONTROL_TERMINATOR):
                control_messages.append(_read_control_message(data))
            elif isinstance(data, bytes):
                binary_messages.append(data)

        file_start = next(m for m in control_messages if m["msg"] == "file_start")
        self.assertEqual(file_start["index"], 0)
        self.assertEqual(file_start["size"], 100)

        file_end = next(m for m in control_messages if m["msg"] == "file_end")
        self.assertEqual(file_end["index"], 0)

        if binary_messages:
            header = binary_messages[0][:struct.calcsize(CHUNK_HEADER_FMT)]
            idx, offset = struct.unpack(CHUNK_HEADER_FMT, header)
            self.assertEqual(idx, 0)
            self.assertEqual(offset, 0)


class TestWebRTCPeerHelpers(unittest.TestCase):
    def test_encode_control_adds_terminator(self):
        raw = _encode_control({"msg": "auth", "opt_code": "123456"})
        self.assertTrue(raw.endswith(CONTROL_TERMINATOR))
        parsed = _read_control_message(raw)
        self.assertEqual(parsed["msg"], "auth")
        self.assertEqual(parsed["opt_code"], "123456")

    def test_read_control_message_binary(self):
        raw = _encode_control({"msg": "ping"})
        parsed = _read_control_message(raw)
        self.assertEqual(parsed["msg"], "ping")

    def test_read_control_message_string(self):
        parsed = _read_control_message('{"msg":"ping"}\n\n')
        self.assertEqual(parsed["msg"], "ping")

    def test_read_control_message_invalid(self):
        self.assertIsNone(_read_control_message(b"not json\n\n"))

    def test_estimate_chunk_count_small(self):
        self.assertEqual(_estimate_chunk_count(100), 1)

    def test_estimate_chunk_count_exact(self):
        self.assertEqual(_estimate_chunk_count(MAX_MESSAGE_SIZE), 1)

    def test_estimate_chunk_count_one_over(self):
        self.assertEqual(_estimate_chunk_count(MAX_MESSAGE_SIZE + 1), 2)

    def test_estimate_chunk_count_zero(self):
        self.assertEqual(_estimate_chunk_count(0), 1)


if __name__ == "__main__":
    unittest.main()
