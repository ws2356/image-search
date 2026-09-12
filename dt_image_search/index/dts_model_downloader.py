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
