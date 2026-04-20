from __future__ import annotations

import os
from functools import lru_cache
from importlib.resources import files

_BUILD_TYPE_ENV_VAR = "DTIS_BUILD_TYPE"
_BUILD_TYPE_PROD = "prod"
_BUILD_TYPE_DEV = "dev"
_SUPPORTED_BUILD_TYPES = {_BUILD_TYPE_PROD, _BUILD_TYPE_DEV}


def _normalize_build_type(raw_value: str | None) -> str | None:
    if raw_value is None:
        return None
    normalized_value = raw_value.strip().lower()
    if normalized_value in _SUPPORTED_BUILD_TYPES:
        return normalized_value
    return None


def _read_build_type_from_resource() -> str | None:
    resource_path = files("dt_image_search").joinpath("resources", "build_vars")
    if not resource_path.is_file():
        return None

    try:
        raw_text = resource_path.read_text(encoding="utf-8")
    except OSError:
        return None

    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = [part.strip() for part in line.split("=", 1)]
        if key != "build_type":
            continue
        normalized_value = _normalize_build_type(value)
        if normalized_value is None:
            return None
        return normalized_value
    return None


@lru_cache(maxsize=1)
def get_build_type() -> str:
    env_build_type = os.getenv(_BUILD_TYPE_ENV_VAR)
    normalized_env_build_type = _normalize_build_type(env_build_type)
    if normalized_env_build_type is not None:
        return normalized_env_build_type

    resource_build_type = _read_build_type_from_resource()
    if resource_build_type is not None:
        return resource_build_type
    return _BUILD_TYPE_PROD


def get_app_data_segment() -> str:
    return "DTImageSearch-dev" if get_build_type() == _BUILD_TYPE_DEV else "DTImageSearch"


def clear_build_type_cache() -> None:
    get_build_type.cache_clear()
