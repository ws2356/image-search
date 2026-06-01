import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.lifecycle_notifications import (
    build_instant_share_lifecycle_notification,
)


class TestInstantShareLifecycleNotifications(unittest.TestCase):
    def test_done_text_maps_to_clipboard_message(self):
        notification = build_instant_share_lifecycle_notification(
            state="done",
            payload_class="text",
        )

        self.assertIsNotNone(notification)
        self.assertEqual(notification.title, "Instant Share Complete")
        self.assertEqual(notification.message, "Shared text is ready in the clipboard.")
        self.assertEqual(notification.severity, "info")

    def test_failed_uses_error_message(self):
        notification = build_instant_share_lifecycle_notification(
            state="failed",
            payload_class="image",
            error_message="Pinned TLS verification failed.",
        )

        self.assertIsNotNone(notification)
        self.assertEqual(notification.title, "Instant Share Failed")
        self.assertEqual(notification.message, "Pinned TLS verification failed.")
        self.assertEqual(notification.severity, "error")

    def test_negotiating_state_does_not_emit_notification(self):
        notification = build_instant_share_lifecycle_notification(
            state="negotiating",
            payload_class="text",
        )

        self.assertIsNone(notification)


if __name__ == "__main__":
    unittest.main()