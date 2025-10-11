import uuid
import threading
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.bm_context import get_context

_cached_device_id = None
_device_id_lock = threading.Lock()

def get_device_id():
    """
    Returns a unique device ID based on the machine's UUID.
    If the UUID file does not exist, it creates one.
    """
    global _cached_device_id
    if _cached_device_id is not None:
        return _cached_device_id
    
    with _device_id_lock:
        if _cached_device_id is not None:
            return _cached_device_id

        device_id_file = get_app_data_path(get_context()) / "device_id.txt"
        
        if not device_id_file.exists():
            # Generate a new UUID and save it
            device_id = str(uuid.uuid4())
            with open(device_id_file, 'w') as f:
                f.write(device_id)
        else:
            # Read the existing UUID
            with open(device_id_file, 'r') as f:
                device_id = f.read().strip()
        _cached_device_id = device_id
    
    return device_id