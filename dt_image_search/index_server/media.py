# Thumbnail generation and on-disk caching for the index server.
# The web UI references files only by DB file id; file paths never cross the
# wire. Disk cache lives under app_data/thumb_cache (additive-only for the
# data-compatibility constraint).
import hashlib
import os
import threading
from collections import OrderedDict
from pathlib import Path

from PIL import Image

from dt_image_search.pil_image_support import open_pil_image
from pc_common.telemetry.telemetry_client import log
from dt_image_search.model.dts_file import File


class FileGoneError(FileNotFoundError):
    """The DB row exists but the source image is gone from disk."""


class ThumbnailCache:
    """Disk-backed JPEG thumbnails with a bounded in-memory LRU of disk paths."""

    def __init__(self, cache_dir: str, max_memory_items: int = 512):
        self._cache_dir = Path(cache_dir)
        self._max_memory_items = max_memory_items
        self._mem: OrderedDict[str, str] = OrderedDict()
        self._lock = threading.Lock()

    def get_or_build(self, file: File, size: int = 300) -> str:
        key = f"{hashlib.sha1(file.path.encode()).hexdigest()}_{size}.jpg"
        disk_path = self._cache_dir / key
        if disk_path.exists():
            self._remember(key, str(disk_path))
            return str(disk_path)
        self._build(file, size, disk_path)
        self._remember(key, str(disk_path))
        return str(disk_path)

    def _remember(self, key: str, disk_path: str) -> None:
        with self._lock:
            self._mem.pop(key, None)
            self._mem[key] = disk_path
            while len(self._mem) > self._max_memory_items:
                self._mem.popitem(last=False)

    def _build(self, file: File, size: int, disk_path: Path) -> None:
        try:
            with open_pil_image(file.path) as image:
                # Hint decoders (e.g. JPEG) to avoid full-resolution decode —
                # same strategy as index/image_processor.py.
                try:
                    image.draft("RGB", (size, size))
                except Exception:
                    pass
                image = image.convert("RGB")
                image.thumbnail((size, size), Image.Resampling.LANCZOS)
                self._cache_dir.mkdir(parents=True, exist_ok=True)
                tmp_path = disk_path.with_suffix(".tmp")
                image.save(tmp_path, "JPEG", quality=85)
                os.replace(tmp_path, disk_path)  # atomic publish
        except FileNotFoundError as e:
            raise FileGoneError(str(file.path)) from e
        except OSError as e:
            if e.errno in (2, 13):  # ENOENT / EACCES → treat as gone
                raise FileGoneError(str(file.path)) from e
            raise
