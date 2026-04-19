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


def is_mobile_folder_feature_enabled(default: bool = False) -> bool:
    config = get_config()
    mobile_folder_config = config.get("mobile_folder")
    if isinstance(mobile_folder_config, dict) and "enabled" in mobile_folder_config:
        return _as_bool(mobile_folder_config.get("enabled"), default)
    return default


def _as_bool(value, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    return default

def setup_model_cache(ctx: BMContext):
    if ctx.offline_mode:
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['HUGGINGFACE_HUB_CACHE'] = ctx.get_model_cache_path()
