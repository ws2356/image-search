import os
import sys
import time
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler, StashEntry


class TestQRTriggerHandler(unittest.TestCase):

    def setUp(self):
        self.handler = QRTriggerHandler()

    def test_trigger_text_stash(self):
        result = self.handler.handle_trigger({"type": "text", "content": "Hello world"})
        self.assertEqual(result.get("status"), "stashed")
        self.assertIn("stash_id", result)
        self.assertEqual(result.get("content_type"), "text/plain")
        stash_id = result["stash_id"]
        stash = self.handler.get_stash(stash_id)
        self.assertIsNotNone(stash)
        self.assertEqual(stash.content, "Hello world")

    def test_trigger_image_stash(self):
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(b"fake-png-data")
            tmp_path = f.name
        try:
            result = self.handler.handle_trigger({"type": "image", "file_path": tmp_path, "filename": "test.png"})
            self.assertEqual(result.get("status"), "stashed")
            stash_id = result["stash_id"]
            stash = self.handler.get_stash(stash_id)
            self.assertIsNotNone(stash)
            self.assertEqual(stash.file_path, tmp_path)
            self.assertEqual(stash.filename, "test.png")
        finally:
            os.unlink(tmp_path)

    def test_trigger_image_file_not_found(self):
        result = self.handler.handle_trigger({"type": "image", "file_path": "/nonexistent/path.png"})
        self.assertIn("_status", result)
        self.assertEqual(result["_status"], 400)
        self.assertEqual(result.get("error"), "File not found")

    def test_trigger_invalid_type(self):
        result = self.handler.handle_trigger({"type": "video"})
        self.assertEqual(result["_status"], 400)
        self.assertIn("Invalid type", result.get("error", ""))

    def test_trigger_missing_content(self):
        result = self.handler.handle_trigger({"type": "text"})
        self.assertEqual(result["_status"], 400)

    def test_opt_code_generation(self):
        code1 = QRTriggerHandler._generate_opt_code()
        code2 = QRTriggerHandler._generate_opt_code()
        self.assertEqual(len(code1), 6)
        self.assertEqual(len(code2), 6)
        self.assertTrue(code1.isdigit())
        self.assertTrue(code2.isdigit())

    def test_claim_text_success(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "Secret message"})
        stash_id = trigger["stash_id"]
        stash = self.handler.get_stash(stash_id)
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertEqual(result.get("status"), "claimed")
        self.assertEqual(result.get("content"), "Secret message")
        self.assertEqual(result.get("content_type"), "text/plain")

    def test_claim_invalid_opt_code(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "test"})
        stash_id = trigger["stash_id"]
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": "000000"})
        self.assertEqual(result["_status"], 401)
        self.assertEqual(result.get("error"), "Invalid opt-code")

    def test_claim_max_attempts_invalidates(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "test"})
        stash_id = trigger["stash_id"]
        for i in range(3):
            result = self.handler.handle_claim({"stash_id": stash_id, "opt": "000000"})
            if i < 2:
                self.assertEqual(result["_status"], 401)
            else:
                self.assertEqual(result["_status"], 410)
                self.assertIn("Too many failed", result.get("error", ""))

    def test_claim_nonexistent_stash(self):
        result = self.handler.handle_claim({"stash_id": "nonexistent-uuid", "opt": "123456"})
        self.assertEqual(result["_status"], 404)
        self.assertEqual(result.get("error"), "Stash not found")

    def test_claim_expired_stash(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "test"})
        stash_id = trigger["stash_id"]
        stash = self.handler.get_stash(stash_id)
        stash.expired = True
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertEqual(result["_status"], 410)
        self.assertEqual(result.get("error"), "Stash has expired")

    def test_claim_already_claimed(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "test"})
        stash_id = trigger["stash_id"]
        stash = self.handler.get_stash(stash_id)
        stash.claimed = True
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertEqual(result["_status"], 410)
        self.assertEqual(result.get("error"), "Stash already claimed")

    def test_claim_image_file_deleted(self):
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake-jpg-data")
            tmp_path = f.name
        trigger = self.handler.handle_trigger({"type": "image", "file_path": tmp_path, "filename": "test.jpg"})
        stash_id = trigger["stash_id"]
        stash = self.handler.get_stash(stash_id)
        os.unlink(tmp_path)
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertEqual(result["_status"], 410)
        self.assertEqual(result.get("error"), "Source file no longer available")

    def test_expiry_timer_invalidates_stash(self):
        trigger = self.handler.handle_trigger({"type": "text", "content": "timed out"})
        stash_id = trigger["stash_id"]
        stash = self.handler.get_stash(stash_id)
        # Manually expire the stash in the timer handler by setting expires_at in the past
        stash.expires_at = time.time() - 1
        self.handler._on_expiry_timer_fired(stash_id)
        self.assertTrue(stash.expired)
        result = self.handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertEqual(result["_status"], 410)

    def test_callbacks_fired(self):
        created_ids = []
        expired_ids = []
        claimed_ids = []

        handler = QRTriggerHandler(
            on_stash_created=lambda e: created_ids.append(e.stash_id),
            on_stash_expired=lambda sid: expired_ids.append(sid),
            on_stash_claimed=lambda sid: claimed_ids.append(sid),
        )

        trigger = handler.handle_trigger({"type": "text", "content": "callback test"})
        stash_id = trigger["stash_id"]
        self.assertIn(stash_id, created_ids)

        stash = handler.get_stash(stash_id)
        handler.handle_claim({"stash_id": stash_id, "opt": stash.opt_code})
        self.assertIn(stash_id, claimed_ids)

        # trigger expiry
        trigger2 = handler.handle_trigger({"type": "text", "content": "expiry cb"})
        sid2 = trigger2["stash_id"]
        handler._on_expiry_timer_fired(sid2)
        self.assertIn(sid2, expired_ids)

    def test_active_stash(self):
        self.assertIsNone(self.handler.active_stash)
        self.handler.handle_trigger({"type": "text", "content": "active"})
        self.assertIsNotNone(self.handler.active_stash)
        self.assertEqual(self.handler.active_stash.content, "active")

    def test_mime_detection(self):
        self.assertEqual(QRTriggerHandler._detect_mime("photo.png"), "image/png")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.jpg"), "image/jpeg")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.jpeg"), "image/jpeg")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.gif"), "image/gif")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.webp"), "image/webp")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.bmp"), "image/bmp")
        self.assertEqual(QRTriggerHandler._detect_mime("photo.unknown"), "application/octet-stream")


if __name__ == "__main__":
    unittest.main()
