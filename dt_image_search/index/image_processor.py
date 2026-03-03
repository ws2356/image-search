"""
Separate module for image processing workers to avoid GUI import issues.
"""
import torch
import open_clip
from PIL import Image, ImageFile
from dt_image_search.bm_context import BMContext
from dt_image_search.telemetry.telemetry_client import log, with_trace

# Allow loading of truncated images
ImageFile.LOAD_TRUNCATED_IMAGES = True

# Global worker state (loaded once per worker process)
_worker_preprocess = None

def _initialize_worker(ctx: BMContext):
    """Initialize worker process with preloaded model"""
    global _worker_preprocess
    log("debug", message=f"Initializing model in worker [debug]")
    log("info", message=f"Initializing model in worker [info]")
    log("error", message=f"Initializing model in worker [error]")
    
    # Load model once per worker process
    try:
        _model, _, preprocess = open_clip.create_model_and_transforms(ctx.model_name, pretrained=ctx.get_pretrained_model_name_or_path())
        _worker_preprocess = preprocess
        log("info", message=f"Succeeded initializing model in worker")
    except Exception as e:
        print(f"Error initializing model in worker: {e}")
        log("error", message=f"Error initializing model in worker: {e}")
        _worker_preprocess = None

@with_trace("process_image_batch")
def process_image_batch(files):
    """Process a batch of images using the persistent worker's preloaded components"""
    global _worker_preprocess
    
    batch_images = []
    valid_files = []
    invalid_files = []
    deleted_files = []

    log("info", message=f"Processing images: {len(files)}")
    for file in files:
        file_path = file.path
        try:
            image = Image.open(file_path).convert("RGB")
            image_tensor = _worker_preprocess(image)
            batch_images.append(image_tensor)
            valid_files.append(file)
        except Exception as e:
            log("error", message=f"Error processing {file_path}: {e}")
            if isinstance(e, FileNotFoundError):
                deleted_files.append(file)
            else:
                invalid_files.append(file)
                print(f"Error processing {file_path}: {e}")
            continue
    
    if batch_images:
        try:
            batch_tensor = torch.stack(batch_images)
            return batch_tensor, valid_files, deleted_files, invalid_files
        except Exception as e:
            log("error", message=f"Error stacking tensors: {e}")
            print(f"Error stacking tensors: {e}")
    return None, [], [], []
