import os
import time
import torch
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

supported_image_types = ('.jpg', '.jpeg', '.png')

@profile
def query_index(index_path: str, query_text: str) -> typing.List[str]:
    faiss_indices = _query_internal(index_path, query_text)
    with create_db_conn() as conn:
        # Fetch file paths from the database using the indices
        return get_files_by_clip_indices(conn, faiss_indices)


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
_TOP_K = 5


@profile
def _get_model():
    global _model, _preprocess, _tokenizer

    if _model is not None:
        return _model, _preprocess, _tokenizer
    print("before loading model")
    model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
    print("after loading model")
    _preprocess = preprocess
    _tokenizer = open_clip.get_tokenizer('ViT-B-32')
    _model = model.to(_device).eval()
    return _model, _preprocess, _tokenizer


@profile
def _query_internal(index_path: str, query_text: str) -> typing.List[str]:
    index = _get_index(index_path)
    _model, _, _tokenizer = _get_model()
    # --- Encode text query ---
    text_tokens = _tokenizer([query_text]).to(_device)
    with torch.no_grad():
        text_features = _model.encode_text(text_tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    text_vector = text_features.cpu().numpy()
    # --- Search ---
    scores, indices = index.search(text_vector, _TOP_K)

    result = []
    for idx, score in zip(indices[0], scores[0]):
        if score > 0.2:
            result.append(idx)
    return [int(item) for item in result]  # Convert to int for consistency