import os
import uuid
os.environ['KMP_DUPLICATE_LIB_OK'] = 'TRUE'
os.environ['OMP_NUM_THREADS'] = '1'
os.environ['MKL_NUM_THREADS'] = '1'

# import torch
import threading
import time
import typing
# import open_clip
# from torchvision import transforms
import numpy as np
import faiss
import hf_xet
from dt_image_search.model.dts_db import create_db_conn, get_folder_by_id, get_files_by_clip_indices, get_pending_files_for_folder, count_files_in_folder, update_file, mark_files_deleted, delete_folders, delete_files_by_folder_id, get_subfolders, get_file_by_path, update_folder_status
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.index.dts_model_downloader import model_downloaded_event
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File
from dt_image_search.tools.dts_perf import perffunc as profile
from dt_image_search.tools.dts_throttle import ThrottledCallback
from dt_image_search.telemetry.telemetry_client import log, with_trace
from dt_image_search.dts_constants import IS_MODEL_DOWNLOADED
from dt_image_search.base.status_bar_messenger import status_bar_messenger
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor
import atexit
from dt_image_search.index.image_processor import _initialize_worker, process_image_batch
from dt_image_search.bm_context import BMContext
from dt_image_search.tools.dts_util import normalized_folder_path

# TODO: refactor multiprocessing code: move all model/preprocess loading to worker processes
def index_path_for_folder(folder: Folder):
    return f"{get_app_data_path()}/{folder.id}.faiss"

_supported_image_types = (".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".heic", ".heif")

def is_image_file(file_path: str) -> bool:
    file_path = file_path.lower() if file_path else ""
    file_name = os.path.basename(file_path)
    if not file_name or file_name.startswith('.'):
        return False
    return file_name.endswith(_supported_image_types)

@with_trace("query_index")
def query_index(ctx: BMContext, folder_id: int, index_path: str, query_text: str) -> list:
    # Check if folder exists
    with create_db_conn() as conn:
        folder = get_folder_by_id(conn, folder_id)
        if not folder:
            return []
        if not os.path.exists(folder.path):
            return []
    index_score_pairs = _query_internal(index_path, query_text, TOP_K * 5)  # Fetch more to account for deduplication
    # Dedupe by item[0] which is the file id
    seen_ids = set()
    index_score_pairs = [item for item in index_score_pairs if not (item[0] in seen_ids or seen_ids.add(item[0]))]
    with create_db_conn() as conn:
        # Fetch file paths from the database using the indices
        file_paths = get_files_by_clip_indices(conn, folder_id, [item[0] for item in index_score_pairs])
        ret = [(file, pair[1]) for file, pair in zip(file_paths, index_score_pairs) if file is not None]
        # top_k results
        return ret[:TOP_K]

def _query_internal(index_path: str, query_text: str, top_k: int) -> list:
    import torch
    torch.set_grad_enabled(False)
    with torch.inference_mode():
        try:
            index = _get_index(index_path)
        except CorruptFaissIndexError as exc:
            log("error", "query", message=f"Failed to query corrupted FAISS index at {index_path}: {exc}")
            return []
        _model, _, _tokenizer = _get_model()
        # --- Encode text query ---
        text_tokens = _tokenizer([query_text]).to(_get_device())
        text_features = _model.encode_text(text_tokens)
        text_features = text_features / (text_features.norm(dim=-1, keepdim=True) + 1e-10)
        text_vector = text_features.cpu().numpy().astype(np.float32)
        if not text_vector.flags['C_CONTIGUOUS']:
            text_vector = np.ascontiguousarray(text_vector)
        # --- Search ---
        with _get_index_lock(index_path):
            scores, indices = index.search(text_vector, top_k)

        index_score_pairs = zip(indices[0], scores[0])
        index_score_pairs = sorted(index_score_pairs, key=lambda x: x[1], reverse=True)
        return [[int(item[0]), item[1]] for item in index_score_pairs]  # Convert to int for consistency

@profile
def create_index_if_needed(index_path: str):
    with _get_index_lock(index_path):
        if os.path.exists(index_path):
            return
        _create_empty_index(index_path)


# Global process pool that stays alive
_process_pool = None
_pool_lock = threading.Lock()

_index_locks = {}
_index_locks_lock = threading.Lock()

def _get_index_lock(index_path: str) -> threading.Lock:
    with _index_locks_lock:
        if index_path not in _index_locks:
            _index_locks[index_path] = threading.Lock()
        return _index_locks[index_path]


class CorruptFaissIndexError(RuntimeError):
    pass


def _is_faiss_read_error(error: Exception) -> bool:
    if not isinstance(error, RuntimeError):
        return False
    error_text = str(error)
    return "faiss::read_index" in error_text and "read error in" in error_text


def _write_index_atomically(index, index_path: str):
    temp_index_path = f"{index_path}.tmp-{uuid.uuid4().hex}"
    try:
        faiss.write_index(index, temp_index_path)
        os.replace(temp_index_path, index_path)
    finally:
        if os.path.exists(temp_index_path):
            try:
                os.remove(temp_index_path)
            except OSError:
                pass


def _create_empty_index(index_path: str):
    _model, _, _ = _get_model()
    dim = _model.visual.output_dim
    index = faiss.IndexFlatIP(dim)
    index = faiss.IndexIDMap2(index)
    _write_index_atomically(index, index_path)


def _recover_corrupted_index(ctx: BMContext, index_path: str, folder_id: int):
    backup_path = None
    with _get_index_lock(index_path):
        if os.path.exists(index_path):
            backup_path = f"{index_path}.corrupt-{int(time.time())}"
            try:
                os.replace(index_path, backup_path)
            except OSError as exc:
                log("warning", "index", message=f"Failed to backup corrupted FAISS index before recovery: {exc}")
        _create_empty_index(index_path)

    with create_db_conn() as conn:
        conn.execute(
            "UPDATE files SET clip_index = NULL, status = 0 WHERE folder_id = ? AND status != 2",
            (folder_id,),
        )
        conn.commit()
        update_folder_status(conn, folder_id, 1)

    if backup_path:
        log(
            "warning",
            "index",
            message=(
                f"Recovered corrupted FAISS index for folder {folder_id}. "
                f"Backed up old index to {backup_path} and reset folder files for re-indexing."
            ),
        )
    else:
        log(
            "warning",
            "index",
            message=(
                f"Recovered corrupted FAISS index for folder {folder_id}. "
                "Reset folder files for re-indexing."
            ),
        )

def _calculate_worker_count():
    return 1
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

def _get_process_pool(ctx: BMContext) -> ProcessPoolExecutor:
    """Get or create the persistent process pool"""
    global _process_pool
    
    with _pool_lock:
        if _process_pool is None:
            # Calculate worker count based on available memory
            worker_count = _calculate_worker_count()
            _process_pool = ProcessPoolExecutor(
                max_workers=worker_count,
                initializer=_initialize_worker,
                initargs=(ctx,),
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

@with_trace("_add_to_index")
def _add_to_index(ctx: BMContext, index_path: str, folder_id: int, image_files: typing.List[File]) -> bool:
    import torch
    model_downloaded_event.wait()  # Wait for the model to be downloaded

    result = True
    try:
        index = _get_index(index_path)
    except CorruptFaissIndexError:
        _recover_corrupted_index(ctx, index_path, folder_id)
        raise
    model, _, _ = _get_model()
    
    # Use persistent process pool
    pool = _get_process_pool(ctx)
    
    # Split files into batches for multiprocessing
    batch_size = 16
    
    file_batches = []
    for i in range(0, len(image_files), batch_size):
        _batch_files = image_files[i:i + batch_size]
        file_batches.append(_batch_files)
    
    all_features = []
    valid_files = []
    
    # Submit all batches to the persistent pool
    futures = []
    try:
        futures = [pool.submit(process_image_batch, batch) for batch in file_batches]
    except Exception as e:
        log("error", message=f"Failed to pool.submit: {e}")
    
    for i, future in enumerate(futures):
        try:
            batch_tensor, batch_valid_files, deleted_files, _ = future.result(timeout=600)
            if batch_tensor is not None:
                torch.set_grad_enabled(False)
                with torch.inference_mode():
                    # Move to GPU and process with model (this stays in main process)
                    # log("info", message=f"Getting features from batch {i}")
                    batch_tensor = batch_tensor.to(_get_device())
                    features = model.encode_image(batch_tensor)
                    features = features / features.norm(dim=-1, keepdim=True)
                    
                    log("info", message=f"Got features from batch {i}")
                    features_np = features.cpu().numpy().astype(np.float32)
                    if not features_np.flags['C_CONTIGUOUS']:
                        features_np = np.ascontiguousarray(features_np)
                    all_features.append(features_np)
                    valid_files.extend(batch_valid_files)
            
            with create_db_conn() as conn:
                mark_files_deleted(conn, [file.id for file in deleted_files])
                
        except Exception as e:
            log("error", "embedding", message=f"Error processing batch {i} {type(e).__name__}: {e}")
            result = False
            continue

    if not all_features:
        if all(not is_image_file(file.path) for file in image_files):
            return True
        log("warning", "embedding", message="No valid images to add to index")
        return False

    # Rest remains the same
    features_np = np.concatenate(all_features, axis=0)
    ids = np.array([file.id for file in valid_files], dtype='int64')
    
    log("info", message=f"Adding {len(features_np)} images to index with ids: {ids}")
    with _get_index_lock(index_path):
        index.add_with_ids(features_np, ids)
        _write_index_atomically(index, index_path)
    
    with create_db_conn() as conn:
        for file in valid_files:
            update_file(conn, file.id, clip_index=file.id, status=1)
    return result


@with_trace("build_index")
def build_index(ctx: BMContext, index_path: str, folder_id: int):
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

    limit = 100
    total_files = -1
    batch_start = 0
    batch_end = 0
    while True:
        with create_db_conn() as conn:
            if total_files == -1:
                total_files = count_files_in_folder(conn, folder_id)
            files = get_pending_files_for_folder(conn, folder_id, offset=0, limit=limit)
        if not files:
            break
        batch_start = batch_end
        batch_end += len(files)
        
        log("debug", message=f"Processing files batch {batch_start} to {batch_end} for indexing.")
        
        # Filter files that need to be indexed
        files_to_index = [file for file in files if file.clip_index is None and file.status == 0]
        
        batch_result = True
        if files_to_index:
            try:
                batch_result = _add_to_index(ctx, index_path, folder_id, files_to_index)
            except CorruptFaissIndexError:
                log(
                    "error",
                    "index",
                    message=(
                        f"Corrupted FAISS index detected while building folder {folder_id}. "
                        "Recovered index and scheduled full re-index."
                    ),
                )
                batch_result = False
            except Exception as exc:
                log("error", "index", message=f"Unexpected indexing error for folder {folder_id}: {exc}")
                batch_result = False
        else:
            log("info", message=f"No new files to index in batch {batch_start} to {batch_end}.")
            continue
        
        # Yield progress information after each batch
        res = {
            'batch_start': batch_start,
            'batch_end': batch_end,
            'total_files': total_files,
            'files_processed': batch_end,
            'files_in_batch': len(files_to_index),
            'batch_result': batch_result
        }

        log("debug", message=f"Batch add to index result: {res}")
        yield res

# TODO: implement append_to_index
@with_trace("append_to_index")
def append_to_index(ctx: BMContext, index_path: str, folder_id: int, file_paths: list[str] = None):
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
                if file_obj and file_obj.status == 0:
                    batch_file_objs.append(file_obj)
        if not batch_file_objs:
            log("debug", message=f"No new files to index in batch {i_slice} to {i_slice + step}.")
            batch_result = True
        else:
            try:
                batch_result = _add_to_index(ctx, index_path, folder_id, batch_file_objs)
            except CorruptFaissIndexError:
                log(
                    "error",
                    "index",
                    message=(
                        f"Corrupted FAISS index detected while appending folder {folder_id}. "
                        "Recovered index and scheduled full re-index."
                    ),
                )
                batch_result = False
            except Exception as exc:
                log("error", "index", message=f"Unexpected append_to_index error for folder {folder_id}: {exc}")
                batch_result = False
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
    with _get_index_lock(index_path):
        try:
            return faiss.read_index(index_path)
        except RuntimeError as exc:
            if _is_faiss_read_error(exc):
                raise CorruptFaissIndexError(str(exc)) from exc
            raise

@with_trace("delete_folder")
def delete_folder(ctx: BMContext, folder_path: str):
    with create_db_conn() as conn:
        if not folder_path:
            log("warning", "delete", message="No folder path provided for deletion.")
            return
        folders = get_subfolders(conn, normalized_folder_path(folder_path))
        for folder in folders:
            if not folder:
                log("warning", "delete", message=f"Folder {folder_path} does not exist in the database.")
                return
            index_path = index_path_for_folder(folder=folder)
            if os.path.exists(index_path):
                os.remove(index_path)
                log("info", message=f"Removed index file for folder {folder.path} at {index_path}")
            else:
                log("warning", "delete", message=f"No index file found for folder {folder.path} at {index_path}")
            # Remove folder from the database
            delete_folders(conn, [folder.path])
            delete_files_by_folder_id(conn, folder.id)


_device = None
def _get_device():
    import torch
    global _device
    if _device is None:
        _device = "cuda" if torch.cuda.is_available() else "cpu"
    return _device

_model = None
_preprocess = None
_tokenizer = None
TOP_K = 100
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

@with_trace("_preload_model")
def _preload_model(ctx: BMContext):
    import torch
    import open_clip
    """Function to preload the model in background"""
    global _model, _preprocess, _tokenizer
    model_downloaded_event.wait()  # Wait for the model to be downloaded for cn market

    def progress_callback(downloaded_bytes: int, total_bytes: typing.Optional[int], filename: str):
        if total_bytes:
            percent = (downloaded_bytes / total_bytes) * 100
            status_bar_messenger.show_status_message.emit(
                f"Downloading model... {percent:.1f}%"
            )
    _throttled_progress_callback = ThrottledCallback(progress_callback, throttle_interval=1.0)

    _MAX_ATTEMPTS = 3
    for _attempt in range(_MAX_ATTEMPTS):
        try:
            status_bar_messenger.show_status_message.emit("Model init...")
            torch.set_grad_enabled(False)
            log("info", message=f"Attempt {_attempt + 1} before loading model")
            model, _, preprocess = open_clip.create_model_and_transforms(
                ctx.model_name,
                pretrained=ctx.get_pretrained_model_name(),
                download_callback=_throttled_progress_callback
                )
            log("info", message=f"Attempt {_attempt + 1} model downloaded")
            status_bar_messenger.show_status_message.emit("Model downloaded")

            _preprocess = preprocess
            _tokenizer = open_clip.get_tokenizer(ctx.model_name)
            log("info", message=f"Attempt {_attempt + 1} tokenizer init")

            _model = model.to(_get_device()).eval()
            log("info", message=f"Attempt {_attempt + 1} model eval")

            status_bar_messenger.show_status_message.emit("Model inited")
            # with create_db_conn() as conn:
            #     set_config(conn, IS_MODEL_DOWNLOADED, "1")
            break
        except Exception as e:
            log("error", "model", message=f"Attempt {_attempt + 1}. Pretrained: {ctx.get_pretrained_model_name()}. offline: {os.getenv('HF_HUB_OFFLINE', '0')}. cache: {os.getenv('HUGGINGFACE_HUB_CACHE', '')}. model version: {ctx.version}. offline mode: {ctx.offline_mode}. Preloading model failed: {e}")
            if _attempt == _MAX_ATTEMPTS - 1:
                status_bar_messenger.show_status_message.emit("Model load failed")
            else:
                # wait a bit before retrying
                time.sleep(3)
    _model_loaded_event.set()

def init(ctx: BMContext):
    threading.Thread(target=_preload_model, args=(ctx,), daemon=True).start()
