"""Check the main bundle's executable/resource contract without running a build.

Author: Codex
Created: 2026-11-13
"""
import tempfile
import types
import unittest
import sys
import runpy
from unittest.mock import Mock
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC = REPO_ROOT / "dt_image_search" / "DTImageSearch_MainApp.spec"
RUNTIME_HOOK = ("pyi_rth_example", "/hooks/pyi_rth_example.py", "PYSOURCE")


class TestMainBundleContract(unittest.TestCase):
    def setUp(self):
        self.executables = {}
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

        def analysis(scripts, **kwargs):
            self.analysis = types.SimpleNamespace(
                scripts=[RUNTIME_HOOK] + [
                    (Path(source).stem, source, "PYSOURCE") for source in scripts
                ],
                binaries=kwargs["binaries"],
                datas=kwargs["datas"],
                pure=[],
            )
            return self.analysis

        def executable(*args, **kwargs):
            result = types.SimpleNamespace(scripts=args[1], **kwargs)
            self.executables[result.name] = result
            return result

        hooks = types.ModuleType("PyInstaller.utils.hooks")
        hooks.collect_data_files = lambda *args, **kwargs: []
        hooks.copy_metadata = lambda *args: []
        hooks.collect_all = lambda *args: ([], [], [])
        spec_globals = {
            "Analysis": analysis,
            "PYZ": lambda *args: None,
            "EXE": executable,
            "COLLECT": lambda *args, **kwargs: None,
            "BUNDLE": lambda *args, **kwargs: None,
        }
        with (
            patch.dict("sys.modules", {
                "PyInstaller": types.ModuleType("PyInstaller"),
                "PyInstaller.utils": types.ModuleType("PyInstaller.utils"),
                "PyInstaller.utils.hooks": hooks,
            }),
            patch.object(sys, "path", sys.path.copy()),
            patch.dict("os.environ", {"DTIS_BUILD_TYPE": "dev"}),
            patch("tempfile.mkdtemp", return_value=self.temp.name),
        ):
            exec(compile(SPEC.read_text(), str(SPEC), "exec"), spec_globals)

    def test_each_executable_keeps_runtime_hooks_before_its_own_entry(self):
        entries = {
            "AuSearch-dev": "shell_main_entry.py",
            "AuSearchIndexServer": "index_server_main.py",
            "AuSearch-devQtFallback": "__main__.py",
            "InstantShareAgent": "scripts/instant_share_agent_main.py",
        }
        for name, source in entries.items():
            with self.subTest(executable=name):
                scripts = self.executables[name].scripts
                self.assertEqual(scripts[0], RUNTIME_HOOK)
                self.assertEqual([entry[1] for entry in scripts[1:]], [source])
                self.assertTrue((SPEC.parent / source).is_file())

    def test_index_server_has_stdout_for_ready_handshake(self):
        self.assertTrue(self.executables["AuSearchIndexServer"].console)

    def test_bundled_static_resources_resolve_from_the_spec_directory(self):
        static_sources = [
            source for source, target in self.analysis.datas if target == "webui/dist"
        ]
        self.assertEqual(len(static_sources), 1)
        self.assertEqual((SPEC.parent / static_sources[0]).name, "dist")
        self.assertTrue((SPEC.parent / static_sources[0]).parent.joinpath("package.json").is_file())


class TestFrozenIndexEntrypoint(unittest.TestCase):
    def test_worker_dispatch_exits_before_server_cli_runs(self):
        multiprocessing = types.ModuleType("multiprocessing")
        multiprocessing.freeze_support = Mock(side_effect=SystemExit(0))
        server_main = types.ModuleType("dt_image_search.index_server.main")
        server_main.main = Mock()
        with patch.dict("sys.modules", {
            "multiprocessing": multiprocessing,
            "dt_image_search.index_server.main": server_main,
        }):
            with self.assertRaises(SystemExit) as stopped:
                runpy.run_path(str(SPEC.parent / "index_server_main.py"), run_name="__main__")
        self.assertEqual(stopped.exception.code, 0)
        server_main.main.assert_not_called()


if __name__ == "__main__":
    unittest.main()
