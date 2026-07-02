import hashlib
import os
from pathlib import Path
import requests
import threading
import zipfile
import dt_image_search.index.bm_model_spec as bm_model_spec
from dt_image_search.tools.bm_sys import is_cn, is_language_en

class BMContext:
    def __init__(self,
                 version: int,
                 subfolder: str,
                 model_name: str,
                 pretrained_model: str,
                 offline_mode: bool,
                 model_file_info_url: str):
        self.version = version
        self.subfolder = subfolder
        self.model_name = model_name
        self._pretrained_model = pretrained_model
        self.offline_mode = offline_mode
        self._model_file_info_url = model_file_info_url
        self._model_file_info = None

    def get_pretrained_model_name(self) -> str:
            return self._pretrained_model

    def get_model_cache_path(self) -> str:
        from dt_image_search.model.dts_fs import get_app_data_path
        return str(get_app_data_path() / "model_cache")

    def is_local_cache_valid(self) -> bool:
        if self.offline_mode:
            return os.path.exists(self.get_model_cache_path())
        else:
            return False

    def is_downloaded_file_valid(self, file_path) -> bool:
        return _check_md5(file_path, self._get_cache_file_md5())

    def process_downloaded_file(self, tmp_file_path):
        final_path = self.get_model_cache_path()
        Path(final_path).mkdir(parents=True, exist_ok=True)
        # unzip tmp_file_path to final_path
        with zipfile.ZipFile(tmp_file_path, 'r') as zip_ref:
            zip_ref.extractall(final_path)
        os.remove(tmp_file_path)

    def get_model_download_url(self) -> str:
        return self._get_model_file_info()["download_url"]
    
    def _get_cache_file_md5(self) -> str:
        return self._get_model_file_info()["md5"]
    
    def _get_model_file_info(self) -> dict:
        if self.version == 1:
            return self._get_model_file_info() or \
                { "download_url": "https://github.com/ws2356/image-search/releases/download/clip_model-v1/v1.bin", "md5": "2fc036aea9cd7306f5ce7ce6abb8d0bf" }
        elif self.version == 2:
            return self._get_model_file_info() or \
                { "download_url": "https://github.com/ws2356/image-search/releases/download/clip_model-v2/v2.zip", "md5": "92fb01a4fd9ce5e2fb82644aadc81b34" }
        else:
            raise ValueError("Unknown BMContext")

    def _get_model_file_info(self) -> dict:
        if self._model_file_info is None:
            url = self._model_file_info_url
            try:
                response = requests.get(url, timeout=10, allow_redirects=True)
                response.raise_for_status()
                self._model_file_info = response.json()
                if self._model_file_info is None:
                    raise ValueError(f"Model file info for version {self.version} not found.")
            except Exception as e:
                from dt_image_search.telemetry.telemetry_client import log
                log("error", message=f"Failed to fetch model file info from {url}: {e}")
                return None
        return self._model_file_info

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
        from dt_image_search.telemetry.telemetry_client import log
        log("error", message=f"MD5 check failed for {file_path}: {e}")
        return False

_lock = threading.Lock()
_bm_context = None

_v1 = BMContext(
    version=1,
    subfolder="",
    model_name=bm_model_spec.model_name,
    pretrained_model=bm_model_spec.pretrained_model,
    offline_mode=False,
    model_file_info_url="https://imagesearch2.boldman.net/models/info_v1.json")

_v1_offline_mode = BMContext(
    version=1,
    subfolder="",
    model_name=bm_model_spec.model_name,
    pretrained_model=bm_model_spec.pretrained_model,
    offline_mode=True,
    model_file_info_url="https://imagesearch2.boldman.net/models/info_v1.json")

_v2 = BMContext(
    version=2,
    subfolder="v2",
    model_name=bm_model_spec.model_name2,
    pretrained_model=bm_model_spec.pretrained_model2,
    offline_mode=True,
    model_file_info_url="https://imagesearch2.boldman.net/models/info_v2.json")

def get_context():
    global _bm_context
    if _bm_context is None:
        with _lock:
            if _bm_context is None:
                _existing_model_version = _get_existing_model_version()
                _existing_offline_mode = _get_model_offline_mode()
                if _existing_model_version == 1:
                    if _existing_offline_mode:
                        _bm_context = _v1_offline_mode
                    else:
                        _bm_context = _v1
                elif _existing_model_version == 2:
                    _bm_context = _v2
                elif not is_cn():
                # For non-cn users, always use v1 context for better model performance, until later we support model switching.
                    _bm_context = _v1
                elif is_language_en():
                    _bm_context = _v1_offline_mode
                else:
                    _bm_context = _v2
                if _get_existing_model_version() is None:
                    _set_existing_model_version(_bm_context.version)
                if _get_model_offline_mode() is None:
                    _set_model_offline_mode(_bm_context.offline_mode)
                
    return _bm_context

def _get_existing_model_version() -> int | None:
    from dt_image_search.model.dts_db import create_db_conn, get_config
    with create_db_conn() as conn:
        version_str = get_config(conn, "model_version")
        if version_str is not None:
            try:
                return int(version_str)
            except:
                return None
        else:
            return None

def _set_existing_model_version(version: int):
    from dt_image_search.model.dts_db import create_db_conn, set_config
    with create_db_conn() as conn:
        set_config(conn, "model_version", str(version))

def _get_model_offline_mode() -> bool | None:
    from dt_image_search.model.dts_db import create_db_conn, get_config
    with create_db_conn() as conn:
        offline_mode_str = get_config(conn, "model_offline_mode")
        if offline_mode_str is not None:
            return offline_mode_str.lower() == "true"
        else:
            return None

def _set_model_offline_mode(offline_mode: bool):
    from dt_image_search.model.dts_db import create_db_conn, set_config
    with create_db_conn() as conn:
        set_config(conn, "model_offline_mode", str(offline_mode).lower())