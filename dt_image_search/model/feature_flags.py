from __future__ import annotations

import errno
import json
import socket
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from dt_image_search.model.dts_config import (
    is_encryption_feature_enabled,
    is_instant_share_feature_enabled,
    is_mobile_folder_feature_enabled,
    is_strict_security_feature_enabled,
)

_FEATURE_FLAGS_ENDPOINT = "https://api.boldman.net/image-search/features"
_FEATURE_FLAGS_TIMEOUT_SECONDS = 10
_FEATURE_FLAGS_MAX_RETRIES = 3
_FEATURE_FLAGS_RETRY_DELAYS_SECONDS = (0.5, 1.0, 2.0)
_FEATURE_FLAGS_CACHE_FILENAME = "feature_flags_remote_cache.json"
_DEFAULT_DESKTOP_ROOT_TRACE_SAMPLE_RATE = 0.1
# Remote schema key: desktop.telemetry.root_trace_sample_rate
_DESKTOP_ROOT_TRACE_SAMPLE_RATE_KEY = "root_trace_sample_rate"


@dataclass(frozen=True)
class DesktopVersionFlag:
    min_version: str
    required: bool


@dataclass(frozen=True)
class _FeatureDefinition:
    key: str
    extractor: Callable[[dict], object | None]
    default_factory: Callable[[], object | None]
    remote_log_formatter: Callable[[object], str] | None = None
    missing_log_message: str | None = None


class _FeatureFlagStore:
    def __init__(self):
        self._lock = threading.RLock()
        self._values: dict[str, object | None] = {}
        self.refresh_thread = None

    def initialize(self) -> None:
        self.refresh_async()

    def is_mobile_folder_enabled(self) -> bool:
        return bool(self._resolve_value(_MOBILE_FOLDER_FEATURE))

    def is_encryption_enabled(self) -> bool:
        return bool(self._resolve_value(_ENCRYPTION_FEATURE))

    def is_strict_security_enabled(self) -> bool:
        return bool(self._resolve_value(_STRICT_SECURITY_FEATURE))

    def is_instant_share_enabled(self) -> bool:
        return bool(self._resolve_value(_INSTANT_SHARE_FEATURE))

    def desktop_root_trace_sample_rate(self) -> float:
        return float(self._resolve_value(_DESKTOP_ROOT_TRACE_SAMPLE_RATE_FEATURE))

    def version_flag(self) -> DesktopVersionFlag | None:
        resolved = self._resolve_value(_VERSION_FEATURE)
        return resolved if isinstance(resolved, DesktopVersionFlag) else None


    def refresh_async(self) -> None:
        with self._lock:
            if self.refresh_thread is not None:
                return  # Refresh already in progress
            refresh_thread = threading.Thread(
                target=self._refresh_worker,
                name="feature-flags-refresh",
                daemon=True,
            )
            self.refresh_thread = refresh_thread
        refresh_thread.start()

    def _refresh_worker(self) -> None:
        try:
            payload = _fetch_feature_flags_payload()
            _save_cached_feature_flags_payload(payload)
            resolved_remote_values = {
                definition.key: definition.extractor(payload)
                for definition in _REMOTE_FEATURE_DEFINITIONS
            }
            with self._lock:
                # Keep in-memory values stable once a flag has been consumed within a session.
                for definition in _REMOTE_FEATURE_DEFINITIONS:
                    remote_value = resolved_remote_values[definition.key]
                    if remote_value is None:
                        continue
                    if definition.key not in self._values or self._values[definition.key] is None:
                        self._values[definition.key] = remote_value
            for definition in _REMOTE_FEATURE_DEFINITIONS:
                remote_value = resolved_remote_values[definition.key]
                if remote_value is None:
                    if definition.missing_log_message is not None:
                        _log_feature_flags("warning", definition.missing_log_message)
                    continue
                if definition.remote_log_formatter is not None:
                    _log_feature_flags("info", definition.remote_log_formatter(remote_value))
        except RuntimeError as exc:
            _log_feature_flags(
                "warning",
                (
                    "FeatureFlags: failed to refresh remote flags: "
                    f"{exc}. Continuing with cached remote flags when available; otherwise local defaults."
                ),
            )
        finally:
            with self._lock:
                self.refresh_thread = None

    def _resolve_value(self, definition: _FeatureDefinition) -> object | None:
        with self._lock:
            if definition.key in self._values:
                return self._values[definition.key]

            cached_payload = _load_cached_feature_flags_payload()
            cached_value = definition.extractor(cached_payload) if cached_payload is not None else None
            if cached_value is not None:
                self._values[definition.key] = cached_value
                return cached_value

            default_value = definition.default_factory()
            self._values[definition.key] = default_value
            return default_value


def _fetch_feature_flags_payload() -> dict:
    body: bytes | None = None
    last_error: RuntimeError | None = None

    for attempt in range(1, _FEATURE_FLAGS_MAX_RETRIES + 2):
        request = Request(
            _FEATURE_FLAGS_ENDPOINT,
            headers={"Accept": "application/json"},
            method="GET",
        )
        try:
            with urlopen(request, timeout=_FEATURE_FLAGS_TIMEOUT_SECONDS) as response:
                status_code = getattr(response, "status", None)
                if status_code is not None and status_code != 200:
                    raise RuntimeError(f"Feature flag request failed with HTTP {status_code}.")
                body = response.read()
            break
        except HTTPError as exc:
            last_error = RuntimeError(f"Feature flag request failed with HTTP {exc.code}.")
            break
        except URLError as exc:
            if _is_temporary_url_error(exc) and attempt <= _FEATURE_FLAGS_MAX_RETRIES:
                _sleep_before_retry(retry_attempt=attempt, reason=f"network_{exc.reason}")
                continue
            last_error = RuntimeError(f"Feature flag request failed: {_format_url_error_reason(exc)}")
            break

    if last_error is not None:
        raise last_error
    if body is None:
        raise RuntimeError("Feature flag request exceeded retry limit.")

    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Feature flag response is not valid JSON.") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("Feature flag response must be a JSON object.")
    return payload


def _is_temporary_url_error(error: URLError) -> bool:
    reason = error.reason
    if isinstance(reason, socket.timeout):
        return True
    if isinstance(reason, socket.gaierror):
        return True
    if isinstance(reason, TimeoutError):
        return True
    if isinstance(reason, OSError):
        if reason.errno in {errno.EHOSTUNREACH, errno.ENETUNREACH, errno.ETIMEDOUT, errno.ECONNRESET, errno.ENOENT}:
            return True
    if isinstance(reason, str):
        lowered = reason.lower()
        temporary_markers = (
            "temporary failure in name resolution",
            "name or service not known",
            "nodename nor servname provided",
            "timed out",
            "network is unreachable",
            "no route to host",
            "no such file or directory",
        )
        return any(marker in lowered for marker in temporary_markers)
    return False


def _format_url_error_reason(error: URLError) -> str:
    reason = error.reason
    if isinstance(reason, OSError):
        filename = getattr(reason, "filename", None)
        if filename:
            return f"{type(reason).__name__}(errno={reason.errno}, filename={filename}): {reason}"
        return f"{type(reason).__name__}(errno={reason.errno}): {reason}"
    return str(reason)


def _sleep_before_retry(*, retry_attempt: int, reason: str) -> None:
    delay_index = min(max(retry_attempt - 1, 0), len(_FEATURE_FLAGS_RETRY_DELAYS_SECONDS) - 1)
    delay_seconds = _FEATURE_FLAGS_RETRY_DELAYS_SECONDS[delay_index]
    _log_feature_flags(
        "warning",
        (
            "FeatureFlags: temporary request failure "
            f"reason={reason} retry_attempt={retry_attempt}/{_FEATURE_FLAGS_MAX_RETRIES} "
            f"delay_seconds={delay_seconds}"
        ),
    )
    time.sleep(delay_seconds)


def _feature_flags_cache_path() -> Path:
    from dt_image_search.bm_context import get_context
    from dt_image_search.model.dts_fs import get_app_data_path

    return get_app_data_path(get_context()) / _FEATURE_FLAGS_CACHE_FILENAME


def _load_cached_feature_flags_payload() -> dict | None:
    cache_path = _feature_flags_cache_path()
    if not cache_path.exists():
        return None

    try:
        with cache_path.open("r", encoding="utf-8") as cache_file:
            payload = json.load(cache_file)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        _log_feature_flags("warning", f"FeatureFlags: failed to load cached remote flags: {exc}")
        return None

    if not isinstance(payload, dict):
        _log_feature_flags("warning", "FeatureFlags: cached remote flags payload must be a JSON object.")
        return None
    return payload


def _save_cached_feature_flags_payload(payload: dict) -> None:
    cache_path = _feature_flags_cache_path()
    try:
        with cache_path.open("w", encoding="utf-8") as cache_file:
            json.dump(payload, cache_file, ensure_ascii=False)
    except (OSError, TypeError, ValueError) as exc:
        _log_feature_flags("warning", f"FeatureFlags: failed to save cached remote flags: {exc}")


def _extract_mobile_folder_enabled(payload: dict) -> bool | None:
    mobile_folder_payload = payload.get("mobile_folder")
    if not isinstance(mobile_folder_payload, dict):
        return None
    if "enabled" not in mobile_folder_payload:
        return None
    return _to_bool(mobile_folder_payload.get("enabled"))


def _extract_encryption_enabled(payload: dict) -> bool | None:
    encryption_payload = payload.get("encryption")
    if not isinstance(encryption_payload, dict):
        return None
    if "enabled" not in encryption_payload:
        return None
    return _to_bool(encryption_payload.get("enabled"))


def _extract_strict_security_enabled(payload: dict) -> bool | None:
    strict_security_payload = payload.get("strict_security")
    if not isinstance(strict_security_payload, dict):
        return None
    if "enabled" not in strict_security_payload:
        return None
    return _to_bool(strict_security_payload.get("enabled"))


def _extract_instant_share_enabled(payload: dict) -> bool | None:
    instant_share_payload = payload.get("instant_share")
    if not isinstance(instant_share_payload, dict):
        return None
    if "enabled" not in instant_share_payload:
        return None
    return _to_bool(instant_share_payload.get("enabled"))


def _extract_desktop_root_trace_sample_rate(payload: dict) -> float | None:
    desktop_payload = payload.get("desktop")
    if not isinstance(desktop_payload, dict):
        return None
    telemetry_payload = desktop_payload.get("telemetry")
    if not isinstance(telemetry_payload, dict):
        return None
    if _DESKTOP_ROOT_TRACE_SAMPLE_RATE_KEY not in telemetry_payload:
        return None
    return _to_sample_rate(telemetry_payload.get(_DESKTOP_ROOT_TRACE_SAMPLE_RATE_KEY))


def _extract_version_flag(payload: dict) -> DesktopVersionFlag | None:
    version_payload = payload.get("version")
    if not isinstance(version_payload, dict):
        return None
    minimum_version = version_payload.get("min")
    if not isinstance(minimum_version, str):
        return None
    normalized_minimum_version = minimum_version.strip()
    if not normalized_minimum_version or _parse_semantic_version(normalized_minimum_version) is None:
        return None
    if "required" not in version_payload:
        return None
    required = _to_optional_bool(version_payload.get("required"))
    if required is None:
        return None
    return DesktopVersionFlag(min_version=normalized_minimum_version, required=required)


def _to_bool(value) -> bool:
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
    return False


def _to_optional_bool(value) -> bool | None:
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
    return None


def _to_sample_rate(value) -> float | None:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return max(0.0, min(float(value), 1.0))
    if isinstance(value, str):
        try:
            parsed = float(value.strip())
        except ValueError:
            return None
        return max(0.0, min(parsed, 1.0))
    return None


def _parse_semantic_version(version: str) -> tuple[int, ...] | None:
    normalized_version = version.strip()
    if not normalized_version:
        return None
    parts = normalized_version.split(".")
    if not parts:
        return None
    parsed_parts: list[int] = []
    for part in parts:
        numeric_prefix = []
        for char in part:
            if char.isdigit():
                numeric_prefix.append(char)
                continue
            break
        if not numeric_prefix:
            return None
        parsed_parts.append(int("".join(numeric_prefix)))
    while len(parsed_parts) > 1 and parsed_parts[-1] == 0:
        parsed_parts.pop()
    return tuple(parsed_parts)


def _is_version_older(current_version: str, minimum_version: str) -> bool:
    parsed_current_version = _parse_semantic_version(current_version)
    parsed_minimum_version = _parse_semantic_version(minimum_version)
    if parsed_current_version is None or parsed_minimum_version is None:
        return False
    max_length = max(len(parsed_current_version), len(parsed_minimum_version))
    current_components = parsed_current_version + (0,) * (max_length - len(parsed_current_version))
    minimum_components = parsed_minimum_version + (0,) * (max_length - len(parsed_minimum_version))
    return current_components < minimum_components


def _format_bool_feature_log(flag_name: str, value: object) -> str:
    return f"FeatureFlags: remote {flag_name}.enabled={bool(value)}."


def _format_version_feature_log(value: object) -> str:
    version_flag = value if isinstance(value, DesktopVersionFlag) else None
    if version_flag is None:
        return "FeatureFlags: remote version flag is invalid."
    return (
        "FeatureFlags: remote "
        f"version.min={version_flag.min_version} required={version_flag.required}."
    )


_MOBILE_FOLDER_FEATURE = _FeatureDefinition(
    key="mobile_folder",
    extractor=_extract_mobile_folder_enabled,
    default_factory=lambda: is_mobile_folder_feature_enabled(),
    remote_log_formatter=lambda value: _format_bool_feature_log("mobile_folder", value),
    missing_log_message="FeatureFlags: remote payload missing mobile_folder.enabled.",
)
_ENCRYPTION_FEATURE = _FeatureDefinition(
    key="encryption",
    extractor=_extract_encryption_enabled,
    default_factory=lambda: is_encryption_feature_enabled(),
    remote_log_formatter=lambda value: _format_bool_feature_log("encryption", value),
)
_STRICT_SECURITY_FEATURE = _FeatureDefinition(
    key="strict_security",
    extractor=_extract_strict_security_enabled,
    default_factory=lambda: is_strict_security_feature_enabled(),
    remote_log_formatter=lambda value: _format_bool_feature_log("strict_security", value),
)
_INSTANT_SHARE_FEATURE = _FeatureDefinition(
    key="instant_share",
    extractor=_extract_instant_share_enabled,
    default_factory=lambda: is_instant_share_feature_enabled(),
    remote_log_formatter=lambda value: _format_bool_feature_log("instant_share", value),
)
_DESKTOP_ROOT_TRACE_SAMPLE_RATE_FEATURE = _FeatureDefinition(
    key="desktop_root_trace_sample_rate",
    extractor=_extract_desktop_root_trace_sample_rate,
    default_factory=lambda: _DEFAULT_DESKTOP_ROOT_TRACE_SAMPLE_RATE,
    remote_log_formatter=(
        lambda value: (
            "FeatureFlags: remote "
            f"desktop.telemetry.root_trace_sample_rate={float(value)}."
        )
    ),
)
_VERSION_FEATURE = _FeatureDefinition(
    key="version",
    extractor=_extract_version_flag,
    default_factory=lambda: None,
    remote_log_formatter=_format_version_feature_log,
)
_REMOTE_FEATURE_DEFINITIONS = (
    _MOBILE_FOLDER_FEATURE,
    _ENCRYPTION_FEATURE,
    _STRICT_SECURITY_FEATURE,
    _INSTANT_SHARE_FEATURE,
    _DESKTOP_ROOT_TRACE_SAMPLE_RATE_FEATURE,
    _VERSION_FEATURE,
)


def _log_feature_flags(severity: str, message: str) -> None:
    try:
        from dt_image_search.telemetry.telemetry_client import log
    except Exception:
        return
    log(severity, message=message)


_feature_flag_store = _FeatureFlagStore()


def initialize_feature_flags() -> None:
    _feature_flag_store.initialize()


def is_mobile_folder_enabled() -> bool:
    return _feature_flag_store.is_mobile_folder_enabled()


def is_encryption_enabled() -> bool:
    return _feature_flag_store.is_encryption_enabled()


# If enabled:
# 1. mobile app remove redundant opt field in capability exchange requests
def is_strict_security_enabled() -> bool:
    return _feature_flag_store.is_strict_security_enabled()


def is_instant_share_enabled() -> bool:
    # TODO: revert this
    # return _feature_flag_store.is_instant_share_enabled()
    return True


def get_desktop_root_trace_sample_rate() -> float:
    return _feature_flag_store.desktop_root_trace_sample_rate()


def get_version_feature_flag() -> DesktopVersionFlag | None:
    return _feature_flag_store.version_flag()


def get_version_update_requirement(current_version: str) -> DesktopVersionFlag | None:
    version_flag = get_version_feature_flag()
    if version_flag is None:
        return None
    if _is_version_older(current_version, version_flag.min_version):
        return version_flag
    return None


def refresh_feature_flags_async() -> None:
    _feature_flag_store.refresh_async()


def _reset_feature_flags_for_tests() -> None:
    global _feature_flag_store
    _feature_flag_store = _FeatureFlagStore()
