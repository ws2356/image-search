import os
import torch
import threading
import typing
import open_clip
from PIL import Image
from torchvision import transforms
import numpy as np
import faiss
from dt_image_search.model.db import create_db_conn, get_files_by_clip_indices, get_pending_files_for_folder, update_file
from dt_image_search.model.fs import get_app_data_path
from dt_image_search.model.folder import Folder
from dt_image_search.model.file import File
from dt_image_search.tools.perf import perffunc as profile

def index_path_for_folder(folder: Folder):
    return f"{get_app_data_path()}/{folder.id}.faiss"

supported_image_types = (".jpg", ".jpeg", ".png", ".bmp", ".gif")

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


@profile
def add_to_index(index_path: str, image_files: typing.List[File]):
    index = _get_index(index_path)
    model, preprocess, _ = _get_model()
    
    image_features = []
    for file in image_files:
        path = file.path
        try:
            image = Image.open(path).convert("RGB")
            image_input = preprocess(image).unsqueeze(0).to(_device)
            with torch.no_grad():
                features = model.encode_image(image_input)
                features = features / features.norm(dim=-1, keepdim=True)
            image_features.append(features.cpu().numpy())
        except Exception as e:
            print(f"Skipping {path}: {e}")

    # Convert list of tensors to a single tensor
    ids = [file.id for file in image_files]
    print(f"Adding {len(image_features)} images to index with ids: {ids}")
    features_np = torch.cat([torch.from_numpy(f) for f in image_features]).numpy()
    index.add_with_ids(features_np, np.array(ids, dtype='int64'))
    # Save the updated index
    faiss.write_index(index, index_path)
    # Update files setting clip_index to be the file IDs
    with create_db_conn() as conn:
        for file in image_files:
            update_file(
                conn,
                file.id,
                clip_index=file.id,  # Assuming clip_index is the same as file ID
                status=1  # Mark as indexed
            )


@profile
def build_index(index_path: str, folder_id: int):
    """
    Build a FAISS index from images in the given folder path.
    This function will create a new index if it does not exist,
    or update the existing index with new image features.
    """
    create_index_if_needed(index_path)
    with create_db_conn() as conn:
        files = get_pending_files_for_folder(conn, folder_id)
    
    if not files:
        print(f"No files to index for folder ID {folder_id}.")
        return
    # TODO: do this in batches
    for file in files:
        if file.clip_index is None and file.status == 0:
            add_to_index(
                index_path,
                [file])

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
    try:
        print("before loading model")
        model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
        print("after loading model")
        _preprocess = preprocess
        _tokenizer = open_clip.get_tokenizer('ViT-B-32')
        _model = model.to(_device).eval()
    except Exception as e:
        print(f"Preloading model failed: {e}")
    finally:
        _model_loaded_event.set()

def init():
    threading.Thread(target=_preload_model, daemon=True).start()