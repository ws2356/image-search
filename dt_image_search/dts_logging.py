import logging
import sys
from dt_image_search.model.dts_fs import get_app_data_path

def get_other_handlers():
    # # Choose a platform-appropriate app data folder
    # if os.name == "nt":  # Windows
    #     log_dir = Path(os.getenv("APPDATA", ".")) / "DTImageSearch"
    # elif sys.platform == "darwin":  # macOS
    #     log_dir = Path.home() / "Library/Logs/DTImageSearch"
    # else:  # Linux or other
    #     log_dir = Path.home() / ".local/share/DTImageSearch"
    log_dir = get_app_data_path() / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "app.log"

    ret = [
        logging.FileHandler(log_file, encoding="utf-8"),
    ]
    if sys.stdout:
        ret.append(logging.StreamHandler(sys.stdout))
    return ret
