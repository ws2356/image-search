from pathlib import Path
from PySide6.QtCore import QStandardPaths

def get_app_data_path() -> Path:
    APP_NAME = "DTImageSearch"
    base_path = QStandardPaths.writableLocation(QStandardPaths.AppDataLocation)
    data_path = Path(base_path) / APP_NAME
    data_path.mkdir(parents=True, exist_ok=True)
    return data_path