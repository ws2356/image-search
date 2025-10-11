import threading
import dt_image_search.index.bm_model_spec as bm_model_spec

class BMContext:
    def __init__(self, subfolder: str, model_name: str, pretrained_model: str):
        self.subfolder = subfolder
        self.model_name = model_name
        self.pretrained_model = pretrained_model

_lock = threading.Lock()
_bm_context = None

_v1 = BMContext(subfolder="", model_name=bm_model_spec.model_name, pretrained_model=bm_model_spec.pretrained_model)
_v2 = BMContext(subfolder="v2", model_name=bm_model_spec.model_name2, pretrained_model=bm_model_spec.pretrained_model2)

def get_context():
    global _bm_context
    if _bm_context is None:
        with _lock:
            if _bm_context is None:
                from dt_image_search.model.dts_db import create_db_conn, has_any_folder
                with create_db_conn(_v1) as conn:
                    # For quickly shipping v2, we don't migrate from v1 to v2.
                    if has_any_folder(conn):
                        _bm_context = _v1
                    else:
                        _bm_context = _v2
    return _bm_context