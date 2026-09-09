from __future__ import annotations

import json
import os
from enum import Enum
from functools import lru_cache
from importlib.resources import files

_BUILD_TYPE_ENV_VAR = "DTIS_BUILD_TYPE"
_DESKTOP_APP_ENV_VAR = "DTIS_DESKTOP_APP"
BUILD_TYPE_PROD = "prod"
BUILD_TYPE_DEV = "dev"
_SUPPORTED_BUILD_TYPES = {BUILD_TYPE_PROD, BUILD_TYPE_DEV}


class DesktopApp(Enum):
    AU_SEARCH = "au_search"
    SNAP_GET = "snap_get"


def _normalize_build_type(raw_value: str | None) -> str | None:
    if raw_value is None:
        return None
    normalized_value = raw_value.strip().lower()
    if normalized_value in _SUPPORTED_BUILD_TYPES:
        return normalized_value
    return None


def _normalize_desktop_app(raw_value: str) -> DesktopApp:
    try:
        return DesktopApp(raw_value.strip().lower())
    except ValueError as error:
        supported_apps = ", ".join(app.value for app in DesktopApp)
        raise ValueError(
            f"Unsupported desktop app: {raw_value!r}. Expected one of: {supported_apps}."
        ) from error


def _read_string_var_from_resource(key: str) -> str | None:
    resource_path = files("pc_common.resources").joinpath("build_vars")
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
    raw_value = build_vars.get(key)
    if not isinstance(raw_value, str):
        return None
    return raw_value


def _read_build_type_from_resource() -> str | None:
    return _normalize_build_type(_read_string_var_from_resource("build_type"))


def _read_desktop_app_from_resource() -> DesktopApp | None:
    raw_desktop_app = _read_string_var_from_resource("desktop_app")
    if raw_desktop_app is None:
        return None
    return _normalize_desktop_app(raw_desktop_app)


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


@lru_cache(maxsize=1)
def get_desktop_app() -> DesktopApp:
    env_desktop_app = os.getenv(_DESKTOP_APP_ENV_VAR)
    if env_desktop_app:
        return _normalize_desktop_app(env_desktop_app)

    resource_desktop_app = _read_desktop_app_from_resource()
    if resource_desktop_app is not None:
        return resource_desktop_app
    return DesktopApp.AU_SEARCH


def clear_build_type_cache() -> None:
    get_build_type.cache_clear()


def clear_desktop_app_cache() -> None:
    get_desktop_app.cache_clear()
