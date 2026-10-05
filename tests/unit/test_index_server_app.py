# Integration test: the index server process must boot headlessly, print the
# DTS_READY handshake line with its actual port, and serve /health.
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestIndexServerReadyHandshake(unittest.TestCase):
    def test_ready_line_and_health(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            env = dict(os.environ)
            # Redirect app data away from the real user directory.
            for key in ("BM_DATA_PATH_DTImageSearch", "BM_DATA_PATH_DTImageSearch-dev",
                        "BM_DATA_PATH_SnapGet", "BM_DATA_PATH_SnapGet-dev"):
                env[key] = temp_dir

            proc = subprocess.Popen(
                [sys.executable, "-m", "dt_image_search.index_server", "--auth-token", "test-token-xyz", "--skip-model-init"],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                ready_port = None
                deadline = time.time() + 30
                while time.time() < deadline:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    if line.startswith("DTS_READY "):
                        ready_port = int(line.split()[1])
                        break
                self.assertIsNotNone(ready_port, "index server did not print DTS_READY in time")

                with urllib.request.urlopen(f"http://127.0.0.1:{ready_port}/health", timeout=5) as resp:
                    self.assertEqual(resp.status, 200)
            finally:
                proc.terminate()
                proc.wait(timeout=15)


if __name__ == "__main__":
    unittest.main()
