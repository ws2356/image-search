from __future__ import annotations

import json
import os
from functools import lru_cache
from importlib.resources import files

_BUILD_TYPE_ENV_VAR = "DTIS_BUILD_TYPE"
BUILD_TYPE_PROD = "prod"
BUILD_TYPE_DEV = "dev"
_SUPPORTED_BUILD_TYPES = {BUILD_TYPE_PROD, BUILD_TYPE_DEV}


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

    try:
        build_vars = json.loads(raw_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(build_vars, dict):
        return None
    build_type = build_vars.get("build_type")
    if not isinstance(build_type, str):
        return None
    return _normalize_build_type(build_type)


@lru_cache(maxsize=1)
def get_build_type() -> str:
    env_build_type = os.getenv(_BUILD_TYPE_ENV_VAR)
    normalized_env_build_type = _normalize_build_type(env_build_type)
    if normalized_env_build_type is not None:
        return normalized_env_build_type

    resource_build_type = _read_build_type_from_resource()
    if resource_build_type is not None:
        return resource_build_type
    return BUILD_TYPE_PROD


def clear_build_type_cache() -> None:
    get_build_type.cache_clear()
