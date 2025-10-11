import ctypes
import platform

def is_cn() -> bool:
    region = _get_system_region()
    if region.lower() == "cn":
        return True
    return False

def _get_system_region():
    system = platform.system()
    if system == "Windows":
        buf = ctypes.create_unicode_buffer(85)
        if ctypes.windll.kernel32.GetUserDefaultGeoName(buf, len(buf)):
            return buf.value
    if system == "Darwin":
        raise NotImplementedError("macOS region detection is not implemented")
    # Fallback if needed
    return None
