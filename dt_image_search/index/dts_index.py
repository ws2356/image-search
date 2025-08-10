import os
import torch
import threading
import typing
import open_clip
from torchvision import transforms
import numpy as np
import faiss
from dt_image_search.model.dts_db import create_db_conn, get_files_by_clip_indices, get_pending_files_for_folder, update_file
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.index.dts_model_downloader import get_pretrained_model, model_downloaded_event
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File
from dt_image_search.tools.dts_perf import perffunc as profile
from dt_image_search.telemetry.telemetry_client import log
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor
import atexit
from PIL import Image

def index_path_for_folder(folder: Folder):
    return f"{get_app_data_path()}/{folder.id}.faiss"

supported_image_types = (".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp")

@profile
def query_index(folder_id: int, index_path: str, query_text: str) -> list:
    index_score_pairs = _query_internal(index_path, query_text)
    with create_db_conn() as conn:
        # Fetch file paths from the database using the indices
        file_paths = get_files_by_clip_indices(conn, folder_id, [item[0] for item in index_score_pairs])
        return [(file, pair[1]) for file, pair in zip(file_paths, index_score_pairs) if file is not None]

@profile
def _query_internal(index_path: str, query_text: str) -> list:
    index = _get_index(index_path)
    _model, _, _tokenizer = _get_model()
    # --- Encode text query ---
    text_tokens = _tokenizer([query_text]).to(_device)
    with torch.no_grad():
        text_features = _model.encode_text(text_tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    text_vector = text_features.cpu().numpy()
    # --- Search ---
    scores, indices = index.search(text_vector, TOP_K)

    result = []
    index_score_pairs = zip(indices[0], scores[0])
    index_score_pairs = sorted(index_score_pairs, key=lambda x: x[1], reverse=True)
    return [[int(item[0]), item[1]] for item in index_score_pairs if item[1] >= 0.2]  # Convert to int for consistency

@profile
def create_index_if_needed(index_path: str):
    if os.path.exists(index_path):
        return
    # --- Create FAISS index ---
    index = faiss.IndexFlatIP(512)  # TODO: avoid hardcoding dimension, use model's output dimension
    index = faiss.IndexIDMap2(index)  # to keep track of image paths
    # ids = np.arange(len(image_features_np)).astype('int64')
    # index.add_with_ids(image_features_np, ids)
    # --- Save index to disk ---
    faiss.write_index(index, index_path)


def _initialize_worker():
    """Initialize worker process with preloaded model"""
    global _worker_model, _worker_preprocess
    import open_clip
    import torch
    
    # Load model once per worker process
    _, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained=get_pretrained_model())
    _worker_model = None  # We don't need model in worker, just preprocessing
    _worker_preprocess = preprocess

def process_image_batch_persistent(file_paths):
    """Process a batch of images using the persistent worker's preloaded components"""
    from PIL import Image
    import torch
    
    # Use the preloaded preprocess function
    global _worker_preprocess
    
    batch_images = []
    valid_files = []
    
    for file_path in file_paths:
        try:
            log("info", message=f"Proprocessing feature from image: {file_path}")
            image = Image.open(file_path).convert("RGB")
            log("info", message=f"Opened image: {file_path}")
            image_tensor = _worker_preprocess(image)
            log("info", message=f"Preprocessed image: {file_path}")
            batch_images.append(image_tensor)
            valid_files.append(file_path)
        except Exception as e:
            # Note: logging might not work properly across processes
            log("error", message=f"Error processing {file_path}: {e}")
            continue
    
    if batch_images:
        # Stack into batch tensor
        batch_tensor = torch.stack(batch_images)
        return batch_tensor, valid_files
    return None, []

# Global process pool that stays alive
_process_pool = None
_pool_lock = threading.Lock()

def _get_process_pool():
    """Get or create the persistent process pool"""
    global _process_pool
    
    with _pool_lock:
        if _process_pool is None:
            cpu_count = min(mp.cpu_count(), 8)
            _process_pool = ProcessPoolExecutor(
                max_workers=cpu_count,
                initializer=_initialize_worker
            )
            # Register cleanup function
            atexit.register(_cleanup_process_pool)
    
    return _process_pool

def _cleanup_process_pool():
    """Clean up the process pool on exit"""
    global _process_pool
    if _process_pool is not None:
        _process_pool.shutdown(wait=True)
        _process_pool = None

@profile
def add_to_index(index_path: str, image_files: typing.List[File]) -> bool:
    model_downloaded_event.wait()  # Wait for the model to be downloaded

    result = True
    index = _get_index(index_path)
    model, preprocess, _ = _get_model()
    
    # Use persistent process pool
    pool = _get_process_pool()
    
    # Split files into batches for multiprocessing
    batch_size = 16
    
    file_batches = []
    for i in range(0, len(image_files), batch_size):
        batch_files = image_files[i:i + batch_size]
        file_paths = [f.path for f in batch_files]
        file_batches.append(file_paths)
    
    all_features = []
    valid_files = []
    
    # Submit all batches to the persistent pool
    futures = [pool.submit(process_image_batch_persistent, batch) for batch in file_batches]
    
    for i, future in enumerate(futures):
        try:
            batch_tensor, batch_valid_files = future.result(timeout=60)
            
            if batch_tensor is not None:
                # Move to GPU and process with model (this stays in main process)
                log("info", message=f"Getting features from batch {i} {file_batches[i]}")
                batch_tensor = batch_tensor.to(_device)
                with torch.no_grad():
                    features = model.encode_image(batch_tensor)
                    features = features / features.norm(dim=-1, keepdim=True)
                
                features_np = features.cpu().numpy()
                all_features.append(features_np)
                
                log("info", message=f"Got features from batch {i} {file_batches[i]}")
                # Map back to File objects
                batch_start = i * batch_size
                batch_files = image_files[batch_start:batch_start + len(batch_valid_files)]
                valid_files.extend(batch_files)
                
        except Exception as e:
            log("error", "embedding", message=f"Error processing batch {i}: {e}")
            result = False
            continue

    if not all_features:
        log("warning", "embedding", message="No valid images to add to index")
        return False

    # Rest remains the same
    features_np = np.concatenate(all_features, axis=0)
    ids = np.array([file.id for file in valid_files], dtype='int64')
    
    log("info", message=f"Adding {len(features_np)} images to index with ids: {ids}")
    index.add_with_ids(features_np, ids)
    faiss.write_index(index, index_path)
    
    with create_db_conn() as conn:
        for file in valid_files:
            update_file(conn, file.id, clip_index=file.id, status=1)
    return result


@profile
def build_index(index_path: str, folder_id: int):
    """
    Build a FAISS index from images in the given folder path.
    This function will create a new index if it does not exist,
    or update the existing index with new image features.
    
    Yields:
        dict: Progress information after each batch is processed.
              Contains 'batch_start', 'batch_end', 'total_files', 'files_processed'
    """

    log("info", message=f"Start building index for folder ID {folder_id} at {index_path}")
    _model_loaded_event.wait()  # Ensure model is preloaded before starting indexing

    create_index_if_needed(index_path)
    with create_db_conn() as conn:
        files = get_pending_files_for_folder(conn, folder_id)
    
    if not files:
        log("error", "db", message=f"No files to index for folder ID {folder_id}.")
        return
    
    total_files = len(files)
    step = 100
    files_processed = 0
    
    for i_slice in range(0, len(files), step):
        batch_start = i_slice
        batch_end = min(i_slice + step, total_files)
        files_slice = files[i_slice:batch_end]
        
        log("debug", message=f"Processing slice {batch_start} to {batch_end} for indexing.")
        
        # Filter files that need to be indexed
        files_to_index = [file for file in files_slice if file.clip_index is None and file.status == 0]
        
        batch_result = False
        if files_to_index:
            batch_result = add_to_index(index_path, files_to_index)
            files_processed += len(files_to_index)
        
        # Yield progress information after each batch
        yield {
            'batch_start': batch_start,
            'batch_end': batch_end,
            'total_files': total_files,
            'files_processed': files_processed,
            'files_in_batch': len(files_to_index),
            'batch_result': batch_result
        }

# TODO: cache the index in memory
@profile
def _get_index(index_path: str):
    return _load_index(index_path)


def _load_index(index_path: str):
    if not os.path.exists(index_path):
        raise FileNotFoundError(f"Index file '{index_path}' does not exist.")
    return faiss.read_index(index_path)


_device = "cuda" if torch.cuda.is_available() else "cpu"
_model = None
_preprocess = None
_tokenizer = None
TOP_K = 5
_model_loaded_event = threading.Event()

@profile
def _get_model():
    global _model, _preprocess, _tokenizer, _model_loaded_event

    if _model is not None:
        return _model, _preprocess, _tokenizer
    _model_loaded_event.wait()  # Wait for the model to be preloaded

    if _model is None:
        raise RuntimeError("Model is not loaded. Please ensure the model is preloaded before querying.")
    return _model, _preprocess, _tokenizer

@profile
def _preload_model():
    """Function to preload the model in background"""
    global _model, _preprocess, _tokenizer
    model_downloaded_event.wait()  # Wait for the model to be downloaded

    pretrained = get_pretrained_model()
    try:
        log("info", message="before loading model")
        model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained=pretrained)
        log("info", message="after loading model")
        _preprocess = preprocess
        _tokenizer = open_clip.get_tokenizer('ViT-B-32')
        log("info", message="get tokenizer")
        _model = model.to(_device).eval()
        log("info", message="model eval")
    except Exception as e:
        print(e)
        log("error", "model", message=f"Preloading model failed: {e}")
    finally:
        _model_loaded_event.set()

def init():
    threading.Thread(target=_preload_model, daemon=True).start()
