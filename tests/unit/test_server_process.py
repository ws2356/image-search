# Unit tests for ServerProcess: spawn/handshake/restart-once semantics.
import io
import threading
import unittest
from unittest.mock import patch, MagicMock

from dt_image_search.shell.server_process import ServerProcess


class _FakeProc:
    def __init__(self, stdout_text):
        self.stdout = io.StringIO(stdout_text)
        self._wait_rc = 0
        self.terminated = False

    def wait(self):
        return self._wait_rc

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.terminated = True


class TestServerProcess(unittest.TestCase):
    def _run_with_procs(self, procs):
        """Start ServerProcess with a queue of fake procs; returns (spawns, ready_port, exited, stop)."""
        spawns = []
        ready_port = []
        exited = threading.Event()
        procs_iter = iter(procs)

        def fake_popen(args, **kwargs):
            proc = next(procs_iter)
            spawns.append(args)
            return proc

        server = ServerProcess(on_ready=ready_port.append, on_exit=exited.set, python_exe="py")
        with patch('dt_image_search.shell.server_process.subprocess.Popen', fake_popen):
            server.start()
            for _ in range(100):
                if exited.is_set():
                    break
                threading.Event().wait(0.01)
        return server, spawns, ready_port, exited

    def test_parses_ready_line(self):
        server, spawns, ready_port, exited = self._run_with_procs([
            _FakeProc("some log\nDTS_READY 5173\n"),
            _FakeProc("DTS_READY 5174\n"),
        ])
        self.assertEqual(ready_port, [5173, 5174])  # announced again after restart
        self.assertEqual(exited.is_set(), True)  # EOF → restart → second EOF → exit
        self.assertEqual(len(spawns), 2)  # exactly one restart
        self.assertIn("--auth-token", spawns[0])
        self.assertEqual(server.token, spawns[0][spawns[0].index("--auth-token") + 1])

    def test_stops_restarting_after_first_failure(self):
        server, spawns, _, exited = self._run_with_procs([
            _FakeProc(""), _FakeProc(""), _FakeProc(""),
        ])
        self.assertEqual(len(spawns), 2)  # never a third spawn
        self.assertEqual(exited.is_set(), True)

    def test_stop_terminates_without_restart(self):
        proc = _FakeProc("")
        # keep the reader blocked on an endless stream
        class _Endless(io.StringIO):
            def readline(self):
                threading.Event().wait(0.05)
                return ""
        proc.stdout = _Endless()
        spawns = []

        def fake_popen(args, **kwargs):
            spawns.append(args)
            return proc

        exited = threading.Event()
        server = ServerProcess(on_exit=exited.set, python_exe="py")
        with patch('dt_image_search.shell.server_process.subprocess.Popen', fake_popen):
            server.start()
            server.stop()
        self.assertTrue(proc.terminated)
        self.assertEqual(len(spawns), 1)  # no restart after explicit stop


if __name__ == "__main__":
    unittest.main()
