from __future__ import annotations

import json
import threading
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from dt_image_search.model.dts_config import is_mobile_folder_feature_enabled

_FEATURE_FLAGS_ENDPOINT = "https://api.boldman.net/image-search/features"
_FEATURE_FLAGS_TIMEOUT_SECONDS = 10


class _FeatureFlagStore:
    def __init__(self):
        self._lock = threading.RLock()
        self._mobile_folder_enabled: bool | None = None
        self.refresh_thread = None

    def initialize(self) -> None:
        self.refresh_async()

    def is_mobile_folder_enabled(self) -> bool:
        with self._lock:
            if self._mobile_folder_enabled is not None:
                return self._mobile_folder_enabled
            self._mobile_folder_enabled = is_mobile_folder_feature_enabled()
            return self._mobile_folder_enabled


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
        from dt_image_search.telemetry.telemetry_client import log
        try:
            payload = _fetch_feature_flags_payload()
            remote_enabled = _extract_mobile_folder_enabled(payload)
            if remote_enabled is None:
                log("warning", message="FeatureFlags: remote payload missing mobile_folder.enabled.")
                return
            with self._lock:
                self._mobile_folder_enabled = remote_enabled
            log("info", message=f"FeatureFlags: remote mobile_folder.enabled={remote_enabled}.")
        except RuntimeError as exc:
            log("warning", message=f"FeatureFlags: failed to refresh remote flags: {exc}")


def _fetch_feature_flags_payload() -> dict:
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
    except HTTPError as exc:
        raise RuntimeError(f"Feature flag request failed with HTTP {exc.code}.") from exc
    except URLError as exc:
        raise RuntimeError(f"Feature flag request failed: {exc.reason}") from exc

    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Feature flag response is not valid JSON.") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("Feature flag response must be a JSON object.")
    return payload


def _extract_mobile_folder_enabled(payload: dict) -> bool | None:
    mobile_folder_payload = payload.get("mobile_folder")
    if not isinstance(mobile_folder_payload, dict):
        return None
    if "enabled" not in mobile_folder_payload:
        return None
    return _to_bool(mobile_folder_payload.get("enabled"))


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


_feature_flag_store = _FeatureFlagStore()


def initialize_feature_flags() -> None:
    _feature_flag_store.initialize()


def is_mobile_folder_enabled() -> bool:
    return _feature_flag_store.is_mobile_folder_enabled()


def refresh_feature_flags_async() -> None:
    _feature_flag_store.refresh_async()


def _reset_feature_flags_for_tests() -> None:
    global _feature_flag_store
    _feature_flag_store = _FeatureFlagStore()
