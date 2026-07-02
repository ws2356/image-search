import os
from pathlib import Path
import requests
import threading
import datetime
from dt_image_search.telemetry.telemetry_client import with_trace, log
from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext

model_downloaded_event = threading.Event()

@with_trace("Model.Download")
def _download_pretrained_model(ctx: BMContext):
    try:
        # file exists and md5 matches, skip download
        if ctx.is_local_cache_valid():
            log("debug", message=f"Model already exists at: {ctx.get_model_cache_path()}")
            return

        log("info", message="Start downloading pretrained model")
        tmp_path = f"{ctx.get_model_cache_path()}.tmp"

        try:
            tmp_path_ = Path(tmp_path)
            tmp_path_.unlink(missing_ok=True)
        except:
            log("error", message=f"Failed to remove tmp file: {tmp_path}")

        _cleanup_partial_download(ctx)

        status_bar_messenger.show_status_message.emit("Downloading model...")
        for _ in range(3):
            try:
                _download_with_progress(ctx.get_model_download_url(), tmp_path)
                if ctx.is_downloaded_file_valid(tmp_path):
                    break
                os.remove(tmp_path)
                log("error", message=f"Pretrained model checksum failed")
            except Exception as e:
                log("error", message=f"Pretrained model download failed: {e}")

        ctx.process_downloaded_file(tmp_path)
        log("info", message="Succeeded downloading pretrained model")
        status_bar_messenger.show_status_message.emit("Model downloaded")
    except Exception as e:
        log("error", message=f"Failed to download pretrained model: {e}")
        status_bar_messenger.show_status_message.emit("Model download failed")
        _cleanup_partial_download(ctx)
    finally:
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

def init(ctx: BMContext):
    if ctx.offline_mode:
        threading.Thread(target=_download_pretrained_model, args=(ctx,)).start()
    else:
        model_downloaded_event.set()  # Skip download in non-CN regions
