import os
import time
import torch
import typing
import open_clip
from PIL import Image
from torchvision import transforms
from tqdm import tqdm
import faiss
from dt_image_search.model.db import create_db_conn, get_files_by_clip_indices, get_pending_files_for_folder
from dt_image_search.model.fs import get_app_data_path
from dt_image_search.model.folder import Folder

def index_path_for_folder(folder: Folder):
    return f"{get_app_data_path()}/{folder.id}.faiss"

supported_image_types = ('.jpg', '.jpeg', '.png')

def query_index(index_path: str, query_text: str) -> typing.List[str]:
    faiss_indices = _query_internal(index_path, query_text)
    with create_db_conn() as conn:
        # Fetch file paths from the database using the indices
        return get_files_by_clip_indices(conn, faiss_indices)


def create_index(index_path: str):
    # --- Create FAISS index ---
    index = faiss.IndexFlatIP(512)  # TODO: avoid hardcoding dimension, use model's output dimension
    if os.path.exists(index_path):
        return
    # --- Save index to disk ---
    faiss.write_index(index, index_path)


def add_to_index(index_path: str, image_paths: typing.List[str]):
    index = _get_index(index_path)
    model, preprocess, _ = _get_model()
    
    image_features = []
    for path in image_paths:
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
    features_np = torch.cat(image_features).numpy()
    index.add(features_np)
    # Save the updated index
    faiss.write_index(index, index_path)


def build_index(index_path: str, folder_id: int):
    """
    Build a FAISS index from images in the given folder path.
    This function will create a new index if it does not exist,
    or update the existing index with new image features.
    """
    create_index(index_path)
    with create_db_conn() as conn:
      files = get_pending_files_for_folder(conn, folder_id)
    add_to_index(
        index_path,
        [file.path for file in files if file.clip_index is None and file.status == 0])

# TODO: cache the index in memory
def _get_index(index_path: str):
    return _load_index(index_path)


def _load_index(index_path: str):
    if not os.path.exists(index_path):
        raise FileNotFoundError(f"Index file '{index_path}' does not exist.")
    return faiss.read_index(index_path)


_device = "cuda" if torch.cuda.is_available() else "cpu"
_mode = None
_preprocess = None
_tokenizer = None
_TOP_K = 5


def _get_model():
  if _mode is not None:
    return _mode, _preprocess, _tokenizer
  print("before loading model")
  _model, _, _preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
  print("after loading model")
  _tokenizer = open_clip.get_tokenizer('ViT-B-32')
  _model = _model.to(_device).eval()
  _measure_time("Model loading")
  return _model, _preprocess, _tokenizer


def _query_internal(index_path: str, query_text: str) -> typing.List[str]:
    index = _get_index(index_path)
    _model, _tokenizer, _ = _get_model()
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
    return result


# Performance measurement
_start_time = time.perf_counter()
def _measure_time(msg=""):
    elapsed = time.perf_counter() - _start_time
    print(f"{msg} completed at: {elapsed:.3f} seconds")
    return elapsed