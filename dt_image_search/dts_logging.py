import logging
from logging.handlers import RotatingFileHandler
import sys
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.bm_context import get_context

def get_other_handlers():
    # # Choose a platform-appropriate app data folder
    # if os.name == "nt":  # Windows
    #     log_dir = Path(os.getenv("APPDATA", ".")) / "DTImageSearch"
    # elif sys.platform == "darwin":  # macOS
    #     log_dir = Path.home() / "Library/Logs/DTImageSearch"
    # else:  # Linux or other
    #     log_dir = Path.home() / ".local/share/DTImageSearch"
    log_dir = get_app_data_path(get_context()) / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "app-utf8.log"

    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=10_000_000,
        backupCount=5,
        encoding="utf-8"
    )
    formatter = logging.Formatter(
        '%(asctime)s [pid:%(process)d] %(levelname)s %(name)s %(message)s'
    )
    file_handler.setFormatter(formatter)

    return [file_handler]
