import logging
import os
import sys
from pathlib import Path
from dt_image_search.model.fs import get_app_data_path

def setup_logging():
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

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(),  # Optional: prints to terminal if launched from console
        ]
    )

    logging.info(f"Logging initialized. Log file at: {log_file}")
