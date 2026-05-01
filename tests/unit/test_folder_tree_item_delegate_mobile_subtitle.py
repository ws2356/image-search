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
            total_assets=0,
            last_backup_at=None,
            last_transfer_status="stopped_by_mobile",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Backup stopped: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_formats_completed_backup_timestamp_when_last_transfer_completed(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="",
            transferred_count=0,
            total_assets=0,
            last_backup_at=None,
            last_transfer_status="completed",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Last backup: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_formats_failed_backup_timestamp(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="",
            transferred_count=181,
            total_assets=0,
            last_backup_at=None,
            last_transfer_status="failed",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertRegex(subtitle, r"^Backup failed: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")

    def test_subtitle_text_prioritizes_transferring_state(self):
        subtitle = FolderTreeItemDelegate._subtitle_text(
            transfer_state="transferring",
            transferred_count=7,
            total_assets=20,
            last_backup_at=None,
            last_transfer_status="stopped_by_mobile",
            last_transfer_at="2026-04-09T12:34:56+00:00",
        )
        self.assertEqual(subtitle, "7/20 files transferred")

    def test_transfer_progress_ratio_is_linear_for_known_total(self):
        ratio = FolderTreeItemDelegate._transfer_progress_ratio(
            transferred_count=25,
            total_assets=100,
        )
        self.assertAlmostEqual(ratio, 0.25)

    def test_transfer_progress_ratio_is_zero_without_total(self):
        ratio = FolderTreeItemDelegate._transfer_progress_ratio(
            transferred_count=25,
            total_assets=0,
        )
        self.assertEqual(ratio, 0.0)


if __name__ == "__main__":
    unittest.main()
