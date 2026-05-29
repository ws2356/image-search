"""
Separate module for image processing workers to avoid GUI import issues.
"""
from PIL import Image
from dt_image_search.bm_context import BMContext
from dt_image_search.telemetry.telemetry_client import log, with_trace
from dt_image_search.pil_image_support import open_pil_image

_MAX_EMBEDDING_IMAGE_DIM = 4096

# Global worker state (loaded once per worker process)
_worker_preprocess = None

def _initialize_worker(ctx: BMContext):
    import open_clip
    """Initialize worker process with preloaded model"""
    global _worker_preprocess
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
    import torch
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
            with open_pil_image(file_path) as image:
                # Hint decoders (e.g. JPEG) to avoid full-resolution decode when possible.
                try:
                    image.draft("RGB", (_MAX_EMBEDDING_IMAGE_DIM, _MAX_EMBEDDING_IMAGE_DIM))
                except Exception:
                    pass

                image = image.convert("RGB")
                if image.width > _MAX_EMBEDDING_IMAGE_DIM or image.height > _MAX_EMBEDDING_IMAGE_DIM:
                    image.thumbnail((_MAX_EMBEDDING_IMAGE_DIM, _MAX_EMBEDDING_IMAGE_DIM), Image.Resampling.LANCZOS)

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
