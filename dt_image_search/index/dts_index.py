import os
import torch
import threading
import time
import typing
import open_clip
from torchvision import transforms
import numpy as np
import faiss
import hf_xet
from dt_image_search.model.dts_db import create_db_conn, get_files_by_clip_indices, get_pending_files_for_folder, update_file, get_folder_by_path, delete_folders, delete_files_by_folder_id, get_subfolders, get_file_by_path
from dt_image_search.model.dts_fs import get_app_data_path, get_pretrained_model_cache_path
from dt_image_search.index.dts_model_downloader import get_pretrained_model, model_downloaded_event
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File
from dt_image_search.tools.dts_perf import perffunc as profile
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.dts_constants import IS_MODEL_DOWNLOADED
from dt_image_search.base.status_bar_messenger import status_bar_messenger
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor
import atexit
from PIL import Image
from dt_image_search.index.image_processor import _initialize_worker, process_image_batch_persistent

# TODO: refactor multiprocessing code: move all model/preprocess loading to worker processes
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


# Global process pool that stays alive
_process_pool = None
_pool_lock = threading.Lock()

def _calculate_worker_count():
    """Calculate optimal worker count based on available memory"""
    try:
        import psutil
        # Get total memory in GB
        total_memory_gb = psutil.virtual_memory().total / (1024**3)
        
        if total_memory_gb <= 8:
            worker_count = 1
        else:
            # Increase worker count by 1 for each additional 2GB after 8GB
            additional_memory = total_memory_gb - 8
            additional_workers = int(additional_memory / 2)
            worker_count = 1 + additional_workers
        
        # Cap at CPU count to avoid over-subscription
        max_workers = min(worker_count, mp.cpu_count())
        
        log("info", message=f"Memory: {total_memory_gb:.1f}GB, calculated workers: {worker_count}, final workers: {max_workers}")
        return max_workers
        
    except ImportError:
        # Fallback if psutil is not available - use conservative approach
        worker_count = 1
        log("warning", message=f"psutil not available, using conservative worker count: {worker_count}")
        return worker_count

def _get_process_pool():
    """Get or create the persistent process pool"""
    global _process_pool
    
    with _pool_lock:
        if _process_pool is None:
            # Calculate worker count based on available memory
            worker_count = _calculate_worker_count()
            _process_pool = ProcessPoolExecutor(
                max_workers=worker_count,
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
def _add_to_index(index_path: str, image_files: typing.List[File]) -> bool:
    model_downloaded_event.wait()  # Wait for the model to be downloaded

    result = True
    index = _get_index(index_path)
    model, _, _ = _get_model()
    
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
            batch_tensor, batch_valid_files = future.result(timeout=600)
            
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
            log("error", "embedding", message=f"Error processing batch {i} {type(e).__name__}: {e}")
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

    log("info", message=f"Start build_index for folder ID {folder_id} at {index_path}")
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
    
    for i_slice in range(0, total_files, step):
        batch_start = i_slice
        batch_end = min(i_slice + step, total_files)
        files_slice = files[i_slice:batch_end]
        
        log("debug", message=f"Processing slice {batch_start} to {batch_end} for indexing.")
        
        # Filter files that need to be indexed
        files_to_index = [file for file in files_slice if file.clip_index is None and file.status == 0]
        
        batch_result = False
        if files_to_index:
            batch_result = _add_to_index(index_path, files_to_index)
            files_processed += len(files_to_index)
        else:
            log("info", message=f"No new files to index in slice {batch_start} to {batch_end}.")
        
        # Yield progress information after each batch
        res = {
            'batch_start': batch_start,
            'batch_end': batch_end,
            'total_files': total_files,
            'files_processed': files_processed,
            'files_in_batch': len(files_to_index),
            'batch_result': batch_result
        }

        log("debug", message=f"Batch add to index result: {res}")
        yield res

# TODO: implement append_to_index
@profile
def append_to_index(index_path: str, folder_id: int, file_paths: list[str] = None):
    _model_loaded_event.wait()  # Wait for the model to be downloaded
    if not file_paths:
        return
    create_index_if_needed(index_path)
    total_files = len(file_paths)
    step = 100
    files_processed = 0

    for i_slice in range(0, total_files, step):
        batch_files = file_paths[i_slice:i_slice + step]
        log("debug", message=f"Processing batch {i_slice} to {i_slice + step} for appending.")
        batch_file_objs = []
        with create_db_conn() as conn:
            for file_path in batch_files:
                file_obj = get_file_by_path(conn, file_path)
                if file_obj and file_obj.clip_index is None and file_obj.status == 0:
                    batch_file_objs.append(file_obj)
        batch_result = _add_to_index(index_path, batch_file_objs)
        files_processed += len(batch_files) if batch_result else 0
        yield {
            'batch_start': i_slice,
            'batch_end': min(i_slice + step, total_files),
            'total_files': total_files,
            'files_processed': files_processed,
            'files_in_batch': len(batch_files),
            'batch_result': batch_result
        }

    log("info", message=f"Finished appending to index for folder ID {folder_id}. Total files processed: {files_processed}.")

# TODO: cache the index in memory
@profile
def _get_index(index_path: str):
    return _load_index(index_path)


def _load_index(index_path: str):
    if not os.path.exists(index_path):
        raise FileNotFoundError(f"Index file '{index_path}' does not exist.")
    return faiss.read_index(index_path)


def delete_folder(folder_path: str = None):
    with create_db_conn() as conn:
        if not folder_path:
            log("warning", "delete", message="No folder path provided for deletion.")
            return
        folders = get_subfolders(conn, folder_path)
        for folder in folders:
            if not folder:
                log("warning", "delete", message=f"Folder {folder_path} does not exist in the database.")
                return
            index_path = index_path_for_folder(folder)
            if os.path.exists(index_path):
                os.remove(index_path)
                log("info", message=f"Removed index file for folder {folder.path} at {index_path}")
            else:
                log("warning", "delete", message=f"No index file found for folder {folder.path} at {index_path}")
            # Remove folder from the database
            delete_folders(conn, [folder.path])
            delete_files_by_folder_id(conn, folder.id)


_device = "cuda" if torch.cuda.is_available() else "cpu"
_model = None
_preprocess = None
_tokenizer = None
TOP_K = 10
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
    _MAX_ATTEMPTS = 3
    for _attempt in range(_MAX_ATTEMPTS):
        try:
            log("info", message=f"Attempt {_attempt + 1} before loading model")
            model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained=pretrained)
            log("info", message=f"Attempt {_attempt + 1} model downloaded")
            status_bar_messenger.show_status_message.emit("Model downloaded")

            _preprocess = preprocess
            _tokenizer = open_clip.get_tokenizer('ViT-B-32')
            log("info", message=f"Attempt {_attempt + 1} tokenizer init")

            _model = model.to(_device).eval()
            log("info", message=f"Attempt {_attempt + 1} model eval")

            status_bar_messenger.show_status_message.emit("Model inited")
            # with create_db_conn() as conn:
            #     set_config(conn, IS_MODEL_DOWNLOADED, "1")
            break
        except Exception as e:
            log("error", "model", message=f"Attempt {_attempt + 1}. Preloading model failed: {e}")
            if _attempt == _MAX_ATTEMPTS - 1:
                status_bar_messenger.show_status_message.emit("Model load failed")
            else:
                # wait a bit before retrying
                time.sleep(3)
    _model_loaded_event.set()

def init():
    threading.Thread(target=_preload_model, daemon=True).start()
