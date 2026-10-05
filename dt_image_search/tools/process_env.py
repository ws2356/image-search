# Process-level environment setup shared by every AuSearch process entry
# (Qt app, index server, shell). Keeps the numerics/libuv env pinned in one place.
import os


def setup_process_env() -> None:
    # Forced (not setdefault) to preserve the legacy entrypoint behavior.
    os.environ['KMP_DUPLICATE_LIB_OK'] = 'TRUE'
    os.environ['OMP_NUM_THREADS'] = '1'
    os.environ['MKL_NUM_THREADS'] = '1'
