import os
from pathlib import Path
import requests
import threading
import datetime
from pc_common.telemetry.telemetry_client import with_trace, log
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext

model_downloaded_event = threading.Event()
model_download_failed_event = threading.Event()
_download_active = False
_download_state_lock = threading.Lock()

@with_trace("Model.DownloadAttempt")
def _download_pretrained_model(ctx: BMContext):
    global _download_active
    try:
        if ctx.is_local_cache_valid():
            log("debug", message=f"Model already exists at: {ctx.get_model_cache_path()}")
            model_downloaded_event.set()
            return
        tmp_path = f"{ctx.get_model_cache_path()}.tmp"
        try:
            Path(tmp_path).unlink(missing_ok=True)
        except Exception as exc:
            log("error", "model_download", message=f"Failed to remove tmp file: {exc}")
        _cleanup_partial_download(ctx)
        status_bar_messenger.show_status_message.emit("Downloading model...")
        for _ in range(3):
            try:
                _download_with_progress(ctx.get_model_download_url(), tmp_path)
                if ctx.is_downloaded_file_valid(tmp_path):
                    break
                os.remove(tmp_path)
                log("error", "model_download", message="Pretrained model checksum failed")
            except Exception as exc:
                log("error", "model_download", message=f"Pretrained model download failed: {exc}")
        ctx.process_downloaded_file(tmp_path)
        log("info", "model_download", message="Succeeded downloading pretrained model")
        status_bar_messenger.show_status_message.emit("Model downloaded")
        model_downloaded_event.set()
    except Exception as exc:
        log("error", "model_download", message=f"Failed to download pretrained model: {exc}")
        status_bar_messenger.show_status_message.emit("Model download failed")
        _cleanup_partial_download(ctx)
        model_download_failed_event.set()
    finally:
        with _download_state_lock:
            _download_active = False

def retry_model_download(ctx: BMContext):
    global _download_active
    if model_downloaded_event.is_set() and not model_download_failed_event.is_set():
        return
    with _download_state_lock:
        if _download_active:
            if not model_download_failed_event.is_set():
                return
            model_download_failed_event.clear()
            model_downloaded_event.clear()
            return
        model_download_failed_event.clear()
        model_downloaded_event.clear()
        _download_active = True
    threading.Thread(
        target=_download_pretrained_model,
        args=(ctx,),
        name="model-download",
        daemon=True,
    ).start()

def init(ctx: BMContext):
    if ctx.offline_mode:
        threading.Thread(
            target=_download_pretrained_model,
            args=(ctx,),
            name="model-download",
            daemon=True,
        ).start()
    else:
        model_downloaded_event.set()

def _cleanup_partial_download(ctx: BMContext):
    final_path_ = Path(ctx.get_model_cache_path())
    try:
        if final_path_.is_dir():
            import shutil
            shutil.rmtree(str(final_path_))
        else:
            final_path_.unlink(missing_ok=True)
    except:
        log("error", message=f"Failed to remove final cache path: {final_path_}")

def _download_with_progress(url, dest_path, chunk_size=4096):
    downloaded = 0
    headers = {}
    if os.path.exists(dest_path):
        downloaded = os.path.getsize(dest_path)
        headers = {"Range": f"bytes={downloaded}-"}
    response = requests.get(url, stream=True, headers=headers, allow_redirects=True)
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