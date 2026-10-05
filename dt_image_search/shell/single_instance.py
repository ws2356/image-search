# Cross-process single-instance lock for the shell (Qt-free).
# Uses an advisory file lock (flock / msvcrt) so the lock is released
# automatically if the process dies.
import os
import sys
from typing import IO


def acquire_instance_lock(lock_path: str) -> IO | None:
    """Acquire the exclusive instance lock; returns the handle to keep, or
    None when another instance holds it."""
    handle = open(lock_path, "a+")
    try:
        if sys.platform == "win32":
            import msvcrt

            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        handle.write(str(os.getpid()))
        handle.flush()
        return handle
    except OSError:
        handle.close()
        return None


def release_instance_lock(handle: IO | None) -> None:
    if handle is None:
        return
    try:
        if sys.platform == "win32":
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        handle.close()
