from __future__ import annotations

import errno
import json
import socket
import threading
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from dt_image_search.model.dts_config import (
    is_encryption_feature_enabled,
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


class _FeatureFlagStore:
    def __init__(self):
        self._lock = threading.RLock()
        self._mobile_folder_enabled: bool | None = None
        self._encryption_enabled: bool | None = None
        self._strict_security_enabled: bool | None = None
        self._desktop_root_trace_sample_rate: float | None = None
        self.refresh_thread = None

    def initialize(self) -> None:
        self.refresh_async()

    def is_mobile_folder_enabled(self) -> bool:
        with self._lock:
            if self._mobile_folder_enabled is not None:
                return self._mobile_folder_enabled

            cached_payload = _load_cached_feature_flags_payload()
            cached_enabled = _extract_mobile_folder_enabled(cached_payload) if cached_payload is not None else None
            if cached_enabled is not None:
                self._mobile_folder_enabled = cached_enabled
                return self._mobile_folder_enabled

            self._mobile_folder_enabled = is_mobile_folder_feature_enabled()
            return self._mobile_folder_enabled

    def is_encryption_enabled(self) -> bool:
        with self._lock:
            if self._encryption_enabled is not None:
                return self._encryption_enabled

            cached_payload = _load_cached_feature_flags_payload()
            cached_enabled = _extract_encryption_enabled(cached_payload) if cached_payload is not None else None
            if cached_enabled is not None:
                self._encryption_enabled = cached_enabled
                return self._encryption_enabled

            self._encryption_enabled = is_encryption_feature_enabled()
            return self._encryption_enabled

    def is_strict_security_enabled(self) -> bool:
        with self._lock:
            if self._strict_security_enabled is not None:
                return self._strict_security_enabled

            cached_payload = _load_cached_feature_flags_payload()
            cached_enabled = _extract_strict_security_enabled(cached_payload) if cached_payload is not None else None
            if cached_enabled is not None:
                self._strict_security_enabled = cached_enabled
                return self._strict_security_enabled

            self._strict_security_enabled = is_strict_security_feature_enabled()
            return self._strict_security_enabled

    def desktop_root_trace_sample_rate(self) -> float:
        with self._lock:
            if self._desktop_root_trace_sample_rate is not None:
                return self._desktop_root_trace_sample_rate

            cached_payload = _load_cached_feature_flags_payload()
            cached_sample_rate = _extract_desktop_root_trace_sample_rate(cached_payload) if cached_payload is not None else None
            if cached_sample_rate is not None:
                self._desktop_root_trace_sample_rate = cached_sample_rate
                return self._desktop_root_trace_sample_rate

            self._desktop_root_trace_sample_rate = _DEFAULT_DESKTOP_ROOT_TRACE_SAMPLE_RATE
            return self._desktop_root_trace_sample_rate


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
            remote_enabled = _extract_mobile_folder_enabled(payload)
            remote_strict_security_enabled = _extract_strict_security_enabled(payload)
            if remote_strict_security_enabled is not None:
                with self._lock:
                    if self._strict_security_enabled is None:
                        self._strict_security_enabled = remote_strict_security_enabled
            if remote_enabled is None:
                _log_feature_flags("warning", "FeatureFlags: remote payload missing mobile_folder.enabled.")
                if remote_strict_security_enabled is not None:
                    _log_feature_flags("info", f"FeatureFlags: remote strict_security.enabled={remote_strict_security_enabled}.")
                return
            remote_encryption_enabled = _extract_encryption_enabled(payload)
            remote_sample_rate = _extract_desktop_root_trace_sample_rate(payload)
            with self._lock:
                # Only update the in-memory flag if it hasn't been set yet.
                # This is to ensure consistent reading of the flag within a single app session, even if remote refreshes happen mid-session.
                if self._mobile_folder_enabled is None:
                    self._mobile_folder_enabled = remote_enabled
                if self._encryption_enabled is None and remote_encryption_enabled is not None:
                    self._encryption_enabled = remote_encryption_enabled
                if self._desktop_root_trace_sample_rate is None and remote_sample_rate is not None:
                    self._desktop_root_trace_sample_rate = remote_sample_rate
            _log_feature_flags("info", f"FeatureFlags: remote mobile_folder.enabled={remote_enabled}.")
            if remote_encryption_enabled is not None:
                _log_feature_flags("info", f"FeatureFlags: remote encryption.enabled={remote_encryption_enabled}.")
            if remote_strict_security_enabled is not None:
                _log_feature_flags("info", f"FeatureFlags: remote strict_security.enabled={remote_strict_security_enabled}.")
            if remote_sample_rate is not None:
                _log_feature_flags(
                    "info",
                    f"FeatureFlags: remote desktop.telemetry.root_trace_sample_rate={remote_sample_rate}.",
                )
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


def get_desktop_root_trace_sample_rate() -> float:
    return _feature_flag_store.desktop_root_trace_sample_rate()


def refresh_feature_flags_async() -> None:
    _feature_flag_store.refresh_async()


def _reset_feature_flags_for_tests() -> None:
    global _feature_flag_store
    _feature_flag_store = _FeatureFlagStore()
