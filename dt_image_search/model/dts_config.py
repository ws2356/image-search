import json
import logging
import os
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.bm_context import get_context, BMContext

def get_config() -> dict:
    config_path = get_app_data_path(get_context()) / "config.json"
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def get_log_level() -> int:
    config = get_config()
    level_str = config.get("log_level", "INFO")
    return getattr(logging, level_str.upper(), logging.INFO)

def get_debugpy_port() -> int:
    config = get_config()
    return config.get("debugpy_port", 0)

def setup_model_cache(ctx: BMContext):
    if ctx.offline_mode:
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['HUGGINGFACE_HUB_CACHE'] = ctx.get_model_cache_path()