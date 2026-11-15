"""Expose real directory children while keeping file ownership at the registered root.

Author: Codex
Created: 2026-11-16
"""
import os
from pathlib import Path

from dt_image_search.index.dts_index import is_image_file
from dt_image_search.model.dts_db import create_db_conn, get_direct_child_files
from dt_image_search.model.dts_file import File
from dt_image_search.model.dts_folder import Folder


def browse_directory(folder: Folder, path: str | None = None) -> tuple[list[Folder], list[File]]:
    """List immediate directories and indexed images within a registered root.

    Subdirectories are navigation targets, not additional database folders.
    Reject paths and symlinks that escape the root, including sibling prefixes.
    """
    root = Path(os.path.abspath(folder.path))
    target = Path(os.path.abspath(path or folder.path))
    resolved_root = root.resolve(strict=True)
    if not target.is_relative_to(root) or not target.resolve(strict=True).is_relative_to(resolved_root):
        raise ValueError("directory is outside the registered folder")
    if not target.is_dir():
        raise NotADirectoryError(str(target))

    subfolders = []
    for child in sorted(target.iterdir(), key=lambda entry: (entry.name.casefold(), entry.name)):
        try:
            if not child.is_dir() or not child.resolve(strict=True).is_relative_to(resolved_root):
                continue
        except (OSError, RuntimeError):
            # A child may disappear or become inaccessible during a scan.
            continue
        subfolders.append(Folder(
            id=folder.id,
            path=child.as_posix().rstrip("/") + "/",
            status=folder.status,
            added_at=folder.added_at,
        ))

    with create_db_conn() as conn:
        images = [
            file for file in get_direct_child_files(conn, target.as_posix())
            if file.folder_id == folder.id
            and Path(file.path).parent == target
            and is_image_file(file.path)
        ]
    return subfolders, images
