# Integration test: the index server process must boot headlessly, print the
# DTS_READY handshake line with its actual port, and serve /health.
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestIndexServerReadyHandshake(unittest.TestCase):
    def test_ready_line_and_health(self):
        self._assert_ready_and_health()

    def test_requested_port_serves_health_and_is_announced(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        self._assert_ready_and_health(port=port)

    def test_out_of_range_port_is_rejected(self):
        for port in (-1, 65536):
            with self.subTest(port=port):
                result = subprocess.run(
                    [
                        sys.executable, "-m", "dt_image_search.index_server",
                        "--auth-token", "test-token-xyz", "--port", str(port),
                    ],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("--port must be between 0 and 65535", result.stderr)

    def _assert_ready_and_health(self, port=None):
        with tempfile.TemporaryDirectory() as temp_dir:
            env = dict(os.environ)
            # Redirect app data away from the real user directory.
            for key in ("BM_DATA_PATH_DTImageSearch", "BM_DATA_PATH_DTImageSearch-dev",
                        "BM_DATA_PATH_SnapGet", "BM_DATA_PATH_SnapGet-dev"):
                env[key] = temp_dir

            command = [
                sys.executable, "-m", "dt_image_search.index_server",
                "--auth-token", "test-token-xyz", "--skip-model-init",
            ]
            if port is not None:
                command.extend(["--port", str(port)])
            proc = subprocess.Popen(
                command,
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
                if port is not None:
                    self.assertEqual(ready_port, port)

                with urllib.request.urlopen(f"http://127.0.0.1:{ready_port}/health", timeout=5) as resp:
                    self.assertEqual(resp.status, 200)

                # The server process must wire desktop telemetry so logs are
                # written to the shared app data directory, not only stdout.
                log_file = os.path.join(temp_dir, "logs", "app-utf8.log")
                deadline = time.time() + 10
                while time.time() < deadline and not os.path.exists(log_file):
                    time.sleep(0.2)
                self.assertTrue(os.path.exists(log_file), "index server did not create logs/app-utf8.log")
            finally:
                proc.terminate()
                proc.wait(timeout=15)
                proc.stdout.close()


if __name__ == "__main__":
    unittest.main()
