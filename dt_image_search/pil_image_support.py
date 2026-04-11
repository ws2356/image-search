from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from importlib import import_module
from pathlib import Path
import os
import platform
import shutil
import subprocess
import tempfile

from PIL import Image, ImageFile

from dt_image_search.telemetry.telemetry_client import log

ImageFile.LOAD_TRUNCATED_IMAGES = True
Image.MAX_IMAGE_PIXELS = None

_HEIF_EXTENSIONS = {".heic", ".heif"}
_HEIF_DECODER_ATTEMPTED = False
_HEIF_DECODER_REGISTERED = False
_SIPS_PATH = shutil.which("sips")


@contextmanager
def open_pil_image(image_path: str | Path) -> Iterator[Image.Image]:
    path = str(image_path)
    if _is_heif_file(path):
        _ensure_heif_decoder_registered()

    try:
        with Image.open(path) as image:
            yield image
            return
    except FileNotFoundError:
        raise
    except (OSError, ValueError) as exc:
        with _open_heif_with_native_fallback(path=path, original_error=exc) as image:
            yield image


def _is_heif_file(image_path: str | Path) -> bool:
    return Path(image_path).suffix.lower() in _HEIF_EXTENSIONS


def _ensure_heif_decoder_registered() -> None:
    global _HEIF_DECODER_ATTEMPTED
    global _HEIF_DECODER_REGISTERED

    if _HEIF_DECODER_ATTEMPTED:
        return

    _HEIF_DECODER_ATTEMPTED = True
    try:
        pillow_heif = import_module("pillow_heif")
    except ModuleNotFoundError:
        if _SIPS_PATH is None:
            log(
                "warning",
                "image_decode",
                "pillow-heif is unavailable and no native HEIC fallback exists on this platform.",
                __file__,
            )
        return

    register_heif_opener = getattr(pillow_heif, "register_heif_opener", None)
    if register_heif_opener is None:
        log(
            "error",
            "image_decode",
            "pillow_heif.register_heif_opener is unavailable; HEIC decoding may fail.",
            __file__,
        )
        return

    try:
        register_heif_opener()
    except (OSError, RuntimeError) as exc:
        log(
            "error",
            "image_decode",
            f"Failed to register pillow-heif decoder support: {exc}",
            __file__,
        )
        return

    _HEIF_DECODER_REGISTERED = True
    log("info", "image_decode", "Registered pillow-heif HEIC/HEIF decoder support.", __file__)


@contextmanager
def _open_heif_with_native_fallback(path: str, original_error: Exception) -> Iterator[Image.Image]:
    if not _is_heif_file(path):
        raise original_error

    if platform.system() != "Darwin" or _SIPS_PATH is None:
        raise original_error

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temporary_file:
        temp_path = Path(temporary_file.name)

    try:
        command = [_SIPS_PATH, "-s", "format", "png", path, "--out", str(temp_path)]
        completed_process = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed_process.returncode != 0:
            stderr = completed_process.stderr.strip()
            stdout = completed_process.stdout.strip()
            error_message = stderr or stdout or f"sips exited with code {completed_process.returncode}"
            raise OSError(error_message) from original_error

        log(
            "warning",
            "image_decode",
            (
                "Using macOS-native HEIC/HEIF fallback because the portable decoder "
                f"was unavailable or could not read {os.path.basename(path)}."
            ),
            __file__,
        )
        log(
            "info",
            "image_decode",
            f"Decoded HEIC/HEIF image via macOS native fallback: {os.path.basename(path)}",
            __file__,
        )
        with Image.open(temp_path) as image:
            yield image
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass
