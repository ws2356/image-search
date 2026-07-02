import ctypes
import os
import platform
import threading

_cache_lock = threading.Lock()
_cached_is_cn = None
_cached_is_language_en = None

def is_cn() -> bool:
    global _cached_is_cn
    with _cache_lock:
        if _cached_is_cn is None:
            region = _get_system_region()
            _cached_is_cn = region.lower() == "cn"
        return _cached_is_cn
    return False

def is_language_en() -> bool:
    global _cached_is_language_en
    with _cache_lock:
        if _cached_is_language_en is not None:
            return _cached_is_language_en

        if platform.system() == "Windows":
            buf = ctypes.create_unicode_buffer(85)
            if ctypes.windll.kernel32.GetUserDefaultLocaleName(buf, len(buf)):
                locale_name = buf.value
                if locale_name.startswith("en"):
                    _cached_is_language_en = True
                else:
                    _cached_is_language_en = False
            else:
                _cached_is_language_en = True  # Default to True if unable to determine
        elif platform.system() == "Darwin":
            try:
                import subprocess
                result = subprocess.run(["defaults", "read", "-g", "AppleLocale"], capture_output=True, text=True)
                if result.returncode == 0:
                    locale = result.stdout.strip()
                    if locale.startswith("en"):
                        _cached_is_language_en = True
                    else:
                        _cached_is_language_en = False
                else:
                    _cached_is_language_en = True  # Default to True if unable to determine
            except Exception as e:
                from dt_image_search.telemetry.telemetry_client import log
                log("error", message=f"Failed to get system language on macOS: {e}")
                _cached_is_language_en = True
        return _cached_is_language_en

def _get_system_region():
    system = platform.system()
    if system == "Windows":
        buf = ctypes.create_unicode_buffer(85)
        if ctypes.windll.kernel32.GetUserDefaultGeoName(buf, len(buf)):
            return buf.value
    if system == "Darwin":
        if "PYTEST_CURRENT_TEST" in os.environ:
            return "US"  # Default for macOS for now in tests
        try:
            import subprocess
            result = subprocess.run(["defaults", "read", "-g", "AppleLocale"], capture_output=True, text=True)
            if result.returncode == 0:
                locale = result.stdout.strip()
                if "_" in locale:
                    return locale.split("_")[1]
        except Exception as e:
            from dt_image_search.telemetry.telemetry_client import log
            log("error", message=f"Failed to get system region on macOS: {e}")
        return "US"  # Default for macOS if unable to determine
    # Fallback if needed
    return None
