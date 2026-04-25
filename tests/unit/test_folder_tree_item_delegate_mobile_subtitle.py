import os
import re
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.view.folder_tree_item_delegate import FolderTreeItemDelegate


class TestFolderTreeItemDelegateMobileSubtitle(unittest.TestCase):
    def test_subtitle_text_formats_stopped_backup_timestamp(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="",
            transferred_count=4,
            last_backup_at=None,
            last_transfer_status="stopped_by_mobile",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Backup stopped: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_formats_completed_backup_timestamp_when_last_transfer_completed(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="",
            transferred_count=0,
            last_backup_at=None,
            last_transfer_status="completed",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Last backup: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_formats_failed_backup_timestamp(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="",
            transferred_count=181,
            last_backup_at=None,
            last_transfer_status="failed",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Backup failed: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_prioritizes_transferring_state(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="transferring",
            transferred_count=7,
            last_backup_at=None,
            last_transfer_status="stopped_by_mobile",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertEqual(subtitle, "7 files transferred")


if __name__ == "__main__":
    unittest.main()
