#!/usr/bin/env python3
"""Validate the packaged build metadata to catch identity/resource mismatches.

Author: Codex
Date: 2026-09-06
"""

import argparse
import json
from pathlib import Path
import sys


def _find_build_vars(package_path: Path) -> Path:
    matches = sorted(package_path.rglob("pc_common/resources/build_vars"))
    if not matches:
        raise ValueError(f"No packaged build_vars found under {package_path}")
    if len(matches) != 1:
        matches_text = "\n  ".join(str(match) for match in matches)
        raise ValueError(
            "Expected exactly one packaged build_vars, found "
            f"{len(matches)}:\n  {matches_text}"
        )
    return matches[0]


def validate_build_vars(
    package_path: Path,
    expected_desktop_app: str,
    expected_build_type: str,
) -> Path:
    build_vars_path = _find_build_vars(package_path)
    try:
        build_vars = json.loads(build_vars_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read packaged build_vars {build_vars_path}: {error}") from error

    if not isinstance(build_vars, dict):
        raise ValueError(f"Packaged build_vars must be a JSON object: {build_vars_path}")

    errors = []
    for key, expected_value in (
        ("build_type", expected_build_type),
        ("desktop_app", expected_desktop_app),
    ):
        actual_value = build_vars.get(key)
        if actual_value != expected_value:
            errors.append(f"{key}: expected {expected_value!r}, got {actual_value!r}")

    if errors:
        raise ValueError(
            f"Packaged build_vars validation failed for {build_vars_path}:\n  "
            + "\n  ".join(errors)
        )

    return build_vars_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-path", type=Path, required=True)
    parser.add_argument(
        "--expected-desktop-app",
        choices=["au_search", "snap_get"],
        required=True,
    )
    parser.add_argument("--expected-build-type", choices=["prod", "dev"], required=True)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        build_vars_path = validate_build_vars(
            args.package_path,
            args.expected_desktop_app,
            args.expected_build_type,
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Validated packaged build_vars: {build_vars_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
