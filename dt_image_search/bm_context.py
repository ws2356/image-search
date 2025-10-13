import hashlib
import os
from pathlib import Path
import threading
import zipfile
import dt_image_search.index.bm_model_spec as bm_model_spec
from dt_image_search.tools.bm_sys import is_cn

class BMContext:
    def __init__(self,
                 version: int,
                 subfolder: str,
                 model_name: str,
                 pretrained_model: str,
                 model_download_url: str,
                 offline_mode: bool,
                 cache_file_md5: str
                 ):
        self.version = version
        self.subfolder = subfolder
        self.model_name = model_name
        self.pretrained_model = pretrained_model
        self.model_download_url = model_download_url
        self.offline_mode = offline_mode
        self.cache_file_md5 = cache_file_md5

    def get_pretrained_model_name_or_path(self) -> str:
        if self.version == 1 and self.is_local_cache_valid():
            return self.get_model_cache_path()
        else:
            return self.pretrained_model

    def get_model_cache_path(self) -> str:
        from dt_image_search.model.dts_fs import get_app_data_path
        if self.version == 2:
            return str(get_app_data_path(ctx=self) / "model_cache")
        elif self.version == 1:
            return os.path.join(get_app_data_path(ctx=self), "open_clip_pytorch_model.bin")
        else:
            raise ValueError("Unknown BMContext")

    def is_local_cache_valid(self) -> bool:
        if self.version == 1:
            return os.path.exists(self.get_model_cache_path()) and _check_md5(self.get_model_cache_path(), self.cache_file_md5)
        elif self.version == 2:
            return os.path.exists(self.get_model_cache_path()) and os.path.isdir(self.get_model_cache_path())
        else:
            raise ValueError("Unknown BMContext")

    def is_downloaded_file_valid(self, file_path) -> bool:
        return _check_md5(file_path, self.cache_file_md5)

    def process_downloaded_file(self, tmp_file_path):
        if self.version == 1:
            final_path = self.get_model_cache_path()
            os.rename(tmp_file_path, final_path)
        elif self.version == 2:
            final_path = self.get_model_cache_path()
            Path(final_path).mkdir(parents=True, exist_ok=True)
            # unzip tmp_file_path to final_path
            import zipfile
            with zipfile.ZipFile(tmp_file_path, 'r') as zip_ref:
                zip_ref.extractall(final_path)
            os.remove(tmp_file_path)
        else:
            raise ValueError("Unknown BMContext")

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
    model_download_url="https://imagesearch.boldman.net/open_clip_pytorch_model.bin",
    offline_mode=False,
    cache_file_md5='2fc036aea9cd7306f5ce7ce6abb8d0bf')

_v2 = BMContext(
    version=2,
    subfolder="v2",
    model_name=bm_model_spec.model_name2,
    pretrained_model=bm_model_spec.pretrained_model2,
    model_download_url="https://imagesearch.boldman.net/models/v2.zip",
    offline_mode=True,
    cache_file_md5='92fb01a4fd9ce5e2fb82644aadc81b34')

def get_context():
    global _bm_context
    if _bm_context is None:
        with _lock:
            if _bm_context is None:
                from dt_image_search.model.dts_db import create_db_conn, has_any_folder
                _existing_model_version = _get_existing_model_version()
                if _existing_model_version == 1:
                    _bm_context = _v1
                elif _existing_model_version == 2:
                    _bm_context = _v2
                elif not is_cn():
                # For non-cn users, always use v1 context for better model performance, until later we support model switching.
                    _bm_context = _v1
                else:
                    with create_db_conn(_v1) as conn:
                        # For quickly shipping v2, we don't migrate from v1 to v2.
                        if has_any_folder(conn):
                            _bm_context = _v1
                        else:
                            _bm_context = _v2
                if _get_existing_model_version() is None:
                    _set_existing_model_version(_bm_context.version)
    return _bm_context

def _get_existing_model_version() -> int | None:
    from dt_image_search.model.dts_db import create_db_conn, get_config
    with create_db_conn(_v1) as conn:
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
    with create_db_conn(_v1) as conn:
        set_config(conn, "model_version", str(version))