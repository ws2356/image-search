# Behavior tests for the pretrained-model downloader's retry/resume flow.
# The outermost network boundary (HTTP + checksums) is mocked; everything
# inside (attempt bookkeeping, tmp-file lifecycle, event signalling) is real.
import os
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from dt_image_search.index import dts_model_downloader

_VALID_CONTENT = b"model-data"


class FakeCtx:
    def __init__(self, root: str):
        self.root = Path(root)
        self.processed: list[str] = []

    def get_model_cache_path(self) -> str:
        return str(self.root / "model_cache")

    def is_local_cache_valid(self) -> bool:
        return os.path.exists(self.get_model_cache_path())

    def is_downloaded_file_valid(self, file_path) -> bool:
        return Path(file_path).read_bytes() == _VALID_CONTENT

    def get_model_download_url(self) -> str:
        return "https://mock.invalid/models.tar.gz"

    def process_downloaded_file(self, tmp_file_path):
        self.processed.append(tmp_file_path)


class FakeResponse:
    def __init__(self, status_code, chunks):
        self.status_code = status_code
        self.headers = {"content-length": "7"}
        self._chunks = chunks

    def iter_content(self, chunk_size):
        return iter(self._chunks)


class DtsModelDownloaderTests(unittest.TestCase):
    def setUp(self):
        self._tmp_dir = tempfile.TemporaryDirectory()
        self.ctx = FakeCtx(self._tmp_dir.name)
        self.tmp_path = self.ctx.get_model_cache_path() + ".tmp"
        dts_model_downloader.model_downloaded_event.clear()
        dts_model_download_failed_event = dts_model_downloader.model_download_failed_event
        dts_model_download_failed_event.clear()

    def tearDown(self):
        self._tmp_dir.cleanup()

    def _run(self):
        with unittest.mock.patch.object(dts_model_downloader.time, "sleep") as _sleep:
            try:
                dts_model_downloader._download_pretrained_model(self.ctx)
            except RuntimeError:
                pass  # expected on exhausted retries

    def test_fails_cleanly_without_extraction_when_all_attempts_fail(self):
        """Repeated transfer failures must never feed a broken tmp file into extraction."""
        Path(self.tmp_path).write_bytes(b"stale-partial")
        attempts = []

        def always_fails(url, dest_path, chunk_size=4096):
            attempts.append(1)
            raise ConnectionError("boom")

        with unittest.mock.patch.object(dts_model_downloader, "_download_with_progress", always_fails):
            self._run()

        self.assertEqual(len(attempts), 3)
        self.assertEqual(self.ctx.processed, [])
        self.assertTrue(dts_model_downloader.model_download_failed_event.is_set())
        # the partial tmp stays behind so the next startup can resume it
        self.assertEqual(Path(self.tmp_path).read_bytes(), b"stale-partial")

    def test_partial_tmp_is_preserved_for_resume(self):
        """An existing partial download from a previous run must not be deleted upfront."""
        Path(self.tmp_path).write_bytes(b"partial")
        seen_existing = []

        def fails_but_peeks(url, dest_path, chunk_size=4096):
            seen_existing.append(Path(dest_path).read_bytes())
            raise ConnectionError("boom")

        with unittest.mock.patch.object(dts_model_downloader, "_download_with_progress", fails_but_peeks):
            self._run()

        self.assertEqual(seen_existing, [b"partial", b"partial", b"partial"])
    def test_succeeds_after_one_retry_with_resume(self):
        """First attempt dies mid-stream, second attempt completes from resume."""
        attempts_seen = []
        state = {"first": True}

        def fails_then_succeeds(url, dest_path, chunk_size=4096):
            attempts_seen.append(os.path.getsize(dest_path) if os.path.exists(dest_path) else 0)
            if state.pop("first", False):
                Path(dest_path).write_bytes(b"partial")
                raise ConnectionError("interrupted")
            Path(dest_path).write_bytes(_VALID_CONTENT)

        with unittest.mock.patch.object(dts_model_downloader, "_download_with_progress", fails_then_succeeds):
            self._run()

        # attempt 2 saw the partial file: resume, not a from-scratch redownload
        self.assertEqual(attempts_seen, [0, 7])
        self.assertEqual(self.ctx.processed, [self.tmp_path])
        self.assertTrue(dts_model_downloader.model_downloaded_event.is_set())

    def test_server_ignoring_range_restarts_from_scratch(self):
        """A 200 (no Range support) answer with an existing partial must rewrite, not append."""
        Path(self.tmp_path).write_bytes(b"partial")
        requests_mock = unittest.mock.MagicMock()
        requests_mock.get.return_value = FakeResponse(200, [b"freshe-"])

        with unittest.mock.patch.object(dts_model_downloader.requests, "get", requests_mock.get):
            dts_model_downloader._download_with_progress("https://mock.invalid/models.tar.gz", self.tmp_path)

        self.assertEqual(Path(self.tmp_path).read_bytes(), b"freshe-")

    # this test asserts resume Range header for a partial download
    def test_range_header_sent_for_partial_download(self):
        Path(self.tmp_path).write_bytes(b"partial")
        requests_mock = unittest.mock.MagicMock()
        requests_mock.get.return_value = FakeResponse(206, [b"x"])

        with unittest.mock.patch.object(dts_model_downloader.requests, "get", requests_mock.get):
            dts_model_downloader._download_with_progress("https://mock.invalid/models.tar.gz", self.tmp_path)

        requests_mock.get.assert_called_once()
        self.assertEqual(requests_mock.get.call_args.kwargs.get("headers", {}).get("Range"), "bytes=7-")

    def test_checksum_failure_clears_tmp_and_does_not_extract(self):
        """A fully transferred but corrupt file is dropped, retried, and never extracted."""
        attempts = []

        def writes_corrupt(url, dest_path, chunk_size=4096):
            attempts.append(1)
            Path(dest_path).write_bytes(b"corrupt-data")

        with unittest.mock.patch.object(dts_model_downloader, "_download_with_progress", writes_corrupt):
            self._run()

        self.assertEqual(len(attempts), 3)
        self.assertEqual(self.ctx.processed, [])
        self.assertFalse(os.path.exists(self.tmp_path))
        self.assertTrue(dts_model_downloader.model_download_failed_event.is_set())

    def test_already_valid_cache_skips_download(self):
        Path(self.ctx.get_model_cache_path()).mkdir()
        with unittest.mock.patch.object(dts_model_downloader, "_download_with_progress") as spy:
            self._run()
        spy.assert_not_called()
        self.assertTrue(dts_model_downloader.model_downloaded_event.is_set())


if __name__ == "__main__":
    unittest.main()
