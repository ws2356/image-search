from pathlib import Path
from PySide6.QtCore import QStandardPaths

_data_path = None

def get_app_data_path() -> Path:
    global _data_path
    if _data_path is not None:
        return _data_path
    APP_NAME = "DTImageSearch"
    base_path = QStandardPaths.writableLocation(QStandardPaths.AppDataLocation)
    data_path = Path(base_path) / APP_NAME
    data_path.mkdir(parents=True, exist_ok=True)
    _data_path = data_path
    return _data_path

def get_pretrained_model_cache_path() -> Path:
    return get_app_data_path() / "hf_cache"