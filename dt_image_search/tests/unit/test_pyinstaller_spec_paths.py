# Lint for PyInstaller spec files: relative entry-point script and datas source
# paths are resolved by PyInstaller against the spec file's directory
# (not the repo root or the process CWD), so every relative path referenced in
# a spec must exist when joined with the spec's own directory.
#
# Author: OpenCode agent (glm-5.3-flash)
# Date: 2026-10-07
import glob
import os
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SPECS = [
    REPO_ROOT / "dt_image_search" / "DTImageSearch_MainApp.spec",
    REPO_ROOT / "dt_image_search" / "DTImageSearch_InstantShare.spec",
]

# Matches the first positional list of string literals inside
# Analysis([ 'a.py', ... ]) -- the entry-point scripts.
ANALYSIS_RE = re.compile(r"Analysis\(\s*\[([^\]]*)\]", re.DOTALL)
# Matches literal ("src", "dest") data tuples (skips str(...) expressions).
DATAS_TUPLE_RE = re.compile(r"\(\s*[\"']([^\"']+)[\"']\s*,\s*[\"'][^\"']+[\"']\s*\)")
# Matches the list body of `datas = [...]` / `datas += [...]` assignments.
DATAS_BLOCK_RE = re.compile(r"datas\s*(?:\+=|=)\s*\[([^\]]*)\]", re.DOTALL)


def _extract_list_strings(list_body: str) -> list:
    return re.findall(r"[\"']([^\"']+)[\"']", list_body)


class SpecPathLint(unittest.TestCase):
    def test_all_spec_entry_scripts_and_datas_exist_relative_to_spec_dir(self):
        errors = []
        for spec in SPECS:
            spec_dir = spec.parent
            text = spec.read_text(encoding="utf-8")
            for list_body in ANALYSIS_RE.findall(text):
                for entry in _extract_list_strings(list_body):
                    if not (spec_dir / entry).exists():
                        errors.append(f"{spec.name}: Analysis script '{entry}' does not exist at "
                                      f"{spec_dir / entry}")
            for block in DATAS_BLOCK_RE.findall(text):
                for src in DATAS_TUPLE_RE.findall(block):
                    pattern = str(spec_dir / src)
                    if not glob.glob(pattern):
                        errors.append(f"{spec.name}: datas source '{src}' matches nothing at {pattern}")
        self.assertEqual([], errors, "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
