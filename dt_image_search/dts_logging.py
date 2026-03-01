import logging
from logging.handlers import RotatingFileHandler
import sys
import os
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.bm_context import get_context
from dt_image_search.tools.dt_is_debug import is_debug

def get_other_handlers():
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

    handlers = [file_handler]
    
    # Add StreamHandler for console output in debug mode or during tests
    if is_debug() or "pytest" in sys.modules or "PYTEST_CURRENT_TEST" in os.environ:
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setFormatter(formatter)
        handlers.append(stream_handler)
        
    return handlers
