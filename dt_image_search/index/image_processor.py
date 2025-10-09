"""
Separate module for image processing workers to avoid GUI import issues.
"""
import torch
import open_clip
from PIL import Image
from dt_image_search.index.dts_model_downloader import get_pretrained_model
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.model.dts_db import create_db_conn, update_file

# Global worker state (loaded once per worker process)
_worker_preprocess = None

def _initialize_worker():
    """Initialize worker process with preloaded model"""
    global _worker_preprocess
    
    # Load model once per worker process
    _, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained=get_pretrained_model())
    _worker_preprocess = preprocess

def process_image_batch_persistent(files):
    """Process a batch of images using the persistent worker's preloaded components"""
    global _worker_preprocess
    
    batch_images = []
    valid_files = []

    log("info", message=f"Processing images: {len(files)}")
    for file in files:
        file_path = file.path
        try:
            image = Image.open(file_path).convert("RGB")
            image_tensor = _worker_preprocess(image)
            batch_images.append(image_tensor)
            valid_files.append(file_path)
        except Exception as e:
            log("debug", message=f"Error processing {file_path}: {e}")
            with create_db_conn() as conn:
                update_file(conn, file_id=file.id, status=2)
            continue
    
    if batch_images:
        try:
            batch_tensor = torch.stack(batch_images)
            return batch_tensor, valid_files
        except Exception as e:
            log("error", message=f"Error stacking tensors: {e}")
    return None, []
