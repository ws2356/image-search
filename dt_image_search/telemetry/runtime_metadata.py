from __future__ import annotations

import os
import sys
import warnings
import xml.etree.ElementTree as ET
from pathlib import Path


PACKAGE_TYPE_DEBUG = "debug"
PACKAGE_TYPE_MSIX = "msix"
PACKAGE_TYPE_ATTRIBUTE = "app.package.type"
PACKAGE_LAUNCH_TYPE_ATTRIBUTE = "app.launch.type"
MANIFEST_NAMESPACE = {"appx": "http://schemas.microsoft.com/appx/manifest/foundation/windows10"}



def _candidate_manifest_paths() -> list[Path]:
    candidates = [
        Path(sys.executable).resolve().parent / "AppxManifest.xml",
        Path(sys.executable).resolve().parent.parent / "AppxManifest.xml",
    ]

    unique_candidates = []
    seen = set()
    for candidate in candidates:
        normalized = str(candidate)
        if normalized in seen:
            continue
        seen.add(normalized)
        unique_candidates.append(candidate)
    return unique_candidates


def resolve_package_type() -> str:
    from dt_image_search.tools.dt_is_debug import is_debug

    return PACKAGE_TYPE_DEBUG if is_debug() else PACKAGE_TYPE_MSIX


def _parse_manifest_version(manifest_path: Path) -> str:
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    identity = root.find("appx:Identity", MANIFEST_NAMESPACE)
    if identity is None:
        raise ValueError(f"Missing Identity element in {manifest_path}")

    version = identity.get("Version", "").strip()
    if not version:
        raise ValueError(f"Missing Identity Version attribute in {manifest_path}")
    return version


def resolve_service_version() -> str:
    package_type = resolve_package_type()
    if package_type == PACKAGE_TYPE_DEBUG:
        return ""

    for manifest_path in _candidate_manifest_paths():
        if not manifest_path.exists():
            continue
        try:
            return _parse_manifest_version(manifest_path)
        except (ET.ParseError, OSError, ValueError) as exc:
            warnings.warn(
                f"Failed to resolve service.version from {manifest_path}: {exc}",
                RuntimeWarning,
                stacklevel=2,
            )
            return ""

    warnings.warn(
        "Failed to resolve service.version because AppxManifest.xml was not found",
        RuntimeWarning,
        stacklevel=2,
    )
    return ""


PACKAGE_TYPE = resolve_package_type()
SERVICE_VERSION = resolve_service_version()

_launch_type = os.getenv("UI_TEST", "") == '1' and "test" or "default"

RESOURCE_ATTRIBUTES = {
    "service.version": SERVICE_VERSION,
    PACKAGE_TYPE_ATTRIBUTE: PACKAGE_TYPE,
    PACKAGE_LAUNCH_TYPE_ATTRIBUTE: _launch_type,
}