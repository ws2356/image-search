import ctypes
import hashlib
import os
import platform
import requests
import threading
import datetime
from dt_image_search.model.dts_db import log
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.model.dts_config import get_override_model_path
from dt_image_search.telemetry.telemetry_client import with_trace
from dt_image_search.base.status_bar_messenger import status_bar_messenger

# When model_downloaded_event is set, the `_get_local_pretrained_model_path()` either exists because download success or skipped due to previous download,
# or not exists because download fails. In latter case, fallback to pretrained model name, so that open_clip would download the model from huggingface
model_downloaded_event = threading.Event()

def get_pretrained_model() -> str:
    override_model_path = get_override_model_path()
    if override_model_path:
        return override_model_path
    if _is_cn() and os.path.exists(_get_local_pretrained_model_path()):
        return _get_local_pretrained_model_path()
    return "laion2b_s34b_b79k"

def _is_cn() -> bool:
    region = _get_system_region()
    if region.lower() == "cn":
        return True
    return False

def _get_system_region():
    system = platform.system()
    if system == "Windows":
        buf = ctypes.create_unicode_buffer(85)
        if ctypes.windll.kernel32.GetUserDefaultGeoName(buf, len(buf)):
            return buf.value
    if system == "Darwin":
        raise NotImplementedError("macOS region detection is not implemented")
    # Fallback if needed
    return None


def _get_local_pretrained_model_path():
    return os.path.join(get_app_data_path(), "open_clip_pytorch_model.bin")

_md5_hash = '2fc036aea9cd7306f5ce7ce6abb8d0bf'
_pretrained_model_url = "https://imagesearch.wansong.vip/open_clip_pytorch_model.bin"
# _pretrained_model_url = "http://192.168.50.10/open_clip_pytorch_model.bin"
@with_trace("Model.Download")
def _download_pretrained_model():
    # Download from `_pretrained_model_url` to file location `_get_local_pretrained_model_path`
    try:
        # file exists and md5 matches, skip download
        if os.path.exists(_get_local_pretrained_model_path()) and _check_md5(_get_local_pretrained_model_path(), _md5_hash):
            log("debug", message=f"Model already exists at: {_get_local_pretrained_model_path()}")
            return

        log("info", message="Start downloading pretrained model")
        tmp_path = f"{_get_local_pretrained_model_path()}.tmp"
        status_bar_messenger.show_status_message.emit("Downloading model...")
        _download_with_progress(_pretrained_model_url, tmp_path)
        os.rename(tmp_path, _get_local_pretrained_model_path())
        log("info", message="Succeeded downloading pretrained model")
        status_bar_messenger.show_status_message.emit("Model downloaded")
    except Exception as e:
        log("error", message=f"Failed to download pretrained model: {e}")
        status_bar_messenger.show_status_message.emit("Model download failed")
    finally:
        model_downloaded_event.set()

def _download_with_progress(url, dest_path, chunk_size=4096):
    downloaded = 0
    headers = {}
    if os.path.exists(dest_path):
        downloaded = os.path.getsize(dest_path)
        headers = {"Range": f"bytes={downloaded}-"}
    response = requests.get(url, stream=True, headers=headers)
    if response.status_code not in (200, 206):
        raise Exception(f"Failed to download file: {response.status_code}")

    total_length = response.headers.get("content-length")
    if total_length is not None:
        total_length = int(total_length) + downloaded

    _last_report_time = None
    mode = "ab" if downloaded > 0 else "wb"
    with open(dest_path, mode) as f:
        for chunk in response.iter_content(chunk_size=chunk_size):
            if not chunk:
                continue
            f.write(chunk)
            downloaded += len(chunk)

            # Calculate progress
            percent = downloaded / total_length * 100
            now = datetime.datetime.now()
            if _last_report_time is None or (now - _last_report_time).total_seconds() >= 3 or percent >= 100:
                _last_report_time = now
                status_bar_messenger.show_status_message.emit(f"Downloading model... {percent:.1f}%")
                log("debug", message=f"Download progress: {percent:.1f}%")

if _is_cn():
    threading.Thread(target=_download_pretrained_model).start()
else:
    log("debug", message="Not in CN region, skipping model download")
    model_downloaded_event.set()  # Skip download in non-CN regions

def _check_md5(file_path, expected_md5):
    """Return True if file's md5 matches expected_md5, else False."""
    if not os.path.exists(file_path):
        return False
    hash_md5 = hashlib.md5()
    try:
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest() == expected_md5
    except Exception as e:
        log("error", message=f"MD5 check failed for {file_path}: {e}")
        return False
