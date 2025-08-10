import logging
from dt_image_search.model.dts_fs import get_app_data_path

def get_config() -> dict:
    config_path = get_app_data_path() / "config.json"
    if config_path.exists():
        import json
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def get_log_level() -> int:
    config = get_config()
    level_str = config.get("log_level", "INFO")
    return getattr(logging, level_str.upper(), logging.INFO)

def get_override_model_path() -> str:
    config = get_config()
    return config.get("override_model_path", "")

def get_debugpy_port() -> int:
    config = get_config()
    return config.get("debugpy_port", 0)