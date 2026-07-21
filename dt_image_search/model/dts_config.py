import json
import logging
import os
from importlib.resources import files
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.bm_context import BMContext

def get_config() -> dict:
    config = _read_build_vars_from_resource()
    config_path = get_app_data_path() / "config.json"
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            file_config = json.load(f)
            if isinstance(file_config, dict):
                config.update(file_config)
    return config


def _read_build_vars_from_resource() -> dict:
    resource_path = files("dt_image_search.resources").joinpath("build_vars")
    if not resource_path.is_file():
        return {}
    try:
        raw_text = resource_path.read_text(encoding="utf-8")
        build_vars = json.loads(raw_text)
    except (OSError, json.JSONDecodeError):
        return {}
    if isinstance(build_vars, dict):
        return build_vars
    return {}

def get_log_level() -> int:
    config = get_config()
    level_str = config.get("log_level", "INFO")
    return getattr(logging, level_str.upper(), logging.INFO)

def get_debugpy_port() -> int:
    config = get_config()
    return config.get("debugpy_port", 0)


def get_revision() -> str:
    config = get_config()
    revision = config.get("revision", "")
    return revision if isinstance(revision, str) else str(revision)


def is_mobile_folder_feature_enabled(default: bool = True) -> bool:
    config = get_config()
    mobile_folder_config = config.get("mobile_folder")
    if isinstance(mobile_folder_config, dict) and "enabled" in mobile_folder_config:
        return _as_bool(mobile_folder_config.get("enabled"), default)
    if "mobile_folder.enabled" in config:
        return _as_bool(config.get("mobile_folder.enabled"), default)
    return default


def is_encryption_feature_enabled(default: bool = True) -> bool:
    config = get_config()
    encryption_config = config.get("encryption")
    if isinstance(encryption_config, dict) and "enabled" in encryption_config:
        return _as_bool(encryption_config.get("enabled"), default)
    if "encryption.enabled" in config:
        return _as_bool(config.get("encryption.enabled"), default)
    return default


def is_strict_security_feature_enabled(default: bool = False) -> bool:
    config = get_config()
    strict_security_config = config.get("strict_security")
    if isinstance(strict_security_config, dict) and "enabled" in strict_security_config:
        return _as_bool(strict_security_config.get("enabled"), default)
    if "strict_security.enabled" in config:
        return _as_bool(config.get("strict_security.enabled"), default)
    return default


def is_instant_share_feature_enabled(default: bool = False) -> bool:
    config = get_config()
    instant_share_config = config.get("instant_share")
    if isinstance(instant_share_config, dict) and "enabled" in instant_share_config:
        return _as_bool(instant_share_config.get("enabled"), default)
    if "instant_share.enabled" in config:
        return _as_bool(config.get("instant_share.enabled"), default)
    return default


def get_signal_relay_url() -> str:
    config = get_config()
    relay = config.get("signal_relay_url", "").strip()
    return relay or "wss://dl.boldman.net/relay"


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
