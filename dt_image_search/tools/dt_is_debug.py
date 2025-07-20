import sys

if getattr(sys, 'frozen', False):
    # Running in a bundled app (packaged)
    _is_debug = False
else:
    # Running from source (debug/development mode)
    _is_debug = True

def is_debug() -> bool:
    """Check if the application is running in debug mode."""
    return _is_debug