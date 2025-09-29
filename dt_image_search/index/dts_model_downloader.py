import ctypes
import os
import platform
import requests
import threading
from dt_image_search.model.dts_db import log
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.model.dts_config import get_override_model_path
from dt_image_search.telemetry.telemetry_client import with_trace

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

_pretrained_model_url = "https://imagesearch.wansong.vip/open_clip_pytorch_model.bin"
@with_trace("Model.Download")
def _download_pretrained_model():
    # Download from `_pretrained_model_url` to file location `_get_local_pretrained_model_path`
    try:
        if os.path.exists(_get_local_pretrained_model_path()):
            log("debug", message=f"Model already exists at: {_get_local_pretrained_model_path()}")
            return

        log("info", message="Start downloading pretrained model")
        tmp_path = f"{_get_local_pretrained_model_path()}.tmp"
        _download_with_progress(_pretrained_model_url, tmp_path)
        os.rename(tmp_path, _get_local_pretrained_model_path())
        log("info", message="Succeeded downloading pretrained model")
    except Exception as e:
        log("error", message=f"Failed to download pretrained model: {e}")
    finally:
        model_downloaded_event.set()

def _download_with_progress(url, dest_path, chunk_size=4096, bar_width=50):
    response = requests.get(url, stream=True)
    if response.status_code != 200:
        raise Exception(f"Failed to download file: {response.status_code}")

    total_length = response.headers.get("content-length")
    
    if total_length is None:
        # No content-length header
        log("debug", message="No content-length header, downloading without progress")
        with open(dest_path, "wb") as f:
            f.write(response.content)
        return

    total_length = int(total_length)
    downloaded = 0

    with open(dest_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=chunk_size):
            if not chunk:
                log("debug", message=f"Download completed")
                continue
            f.write(chunk)
            downloaded += len(chunk)

            # Calculate progress
            percent = downloaded / total_length * 100
            log("debug", message=f"Download progress: {percent:.2f}%")

if _is_cn():
    threading.Thread(target=_download_pretrained_model).start()
else:
    log("debug", message="Not in CN region, skipping model download")
    model_downloaded_event.set()  # Skip download in non-CN regions