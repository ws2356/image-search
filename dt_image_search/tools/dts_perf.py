import time
from dt_image_search.dts_logging import logging
from dt_image_search.telemetry.telemetry_client import log

def perffunc(func):
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        duration = time.perf_counter() - start
        log("debug", "perf", message=f"{func.__qualname__} took {duration:.6f} seconds (shallow)")
        return result
    return wrapper

def perfclass(decorator):
    def class_wrapper(cls):
        for name in dir(cls):
            attr = getattr(cls, name)
            if callable(attr):
                setattr(cls, name, decorator(attr))
        return cls
    return class_wrapper