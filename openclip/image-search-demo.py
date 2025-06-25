import os
import time
import torch
import open_clip
from PIL import Image
from torchvision import transforms
from tqdm import tqdm
import faiss

start_time = time.perf_counter()
def measure_time(msg=""):
    elapsed = time.perf_counter() - start_time
    print(f"{msg} completed at: {elapsed:.3f} seconds")
    return elapsed

import faulthandler; faulthandler.enable()

_script_dir = os.path.dirname(os.path.abspath(__file__))

# --- Config ---
IMAGE_FOLDER = f"{_script_dir}/../image-dataset/00000"
QUERY_TEXT = "A bowl of noodles"
TOP_K = 5
knn_index_path = "knn_index.faiss"

# --- Load model ---
device = "cuda" if torch.cuda.is_available() else "cpu"
print("before loading model")
model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
print("after loading model")
tokenizer = open_clip.get_tokenizer('ViT-B-32')
model = model.to(device).eval()
measure_time("Model loading")

# --- Encode images ---
def get_image_db():
    if not os.path.exists(IMAGE_FOLDER):
        raise FileNotFoundError(f"Image folder '{IMAGE_FOLDER}' does not exist.")
    return [os.path.join(IMAGE_FOLDER, fname) for fname in os.listdir(IMAGE_FOLDER) if fname.lower().endswith(('.jpg', '.jpeg', '.png'))]

image_paths = get_image_db()

def get_clip_index():
    # --- Save index to disk ---
    if os.path.exists(knn_index_path):
        index = faiss.read_index(knn_index_path)
        measure_time("Index loading")
        return index

    image_features = []
    print("Encoding images...")
    for fname in tqdm(os.listdir(IMAGE_FOLDER)):
        if not fname.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue

        path = os.path.join(IMAGE_FOLDER, fname)
        try:
            image = Image.open(path).convert("RGB")
            image_input = preprocess(image).unsqueeze(0).to(device)

            with torch.no_grad():
                features = model.encode_image(image_input)
                features = features / features.norm(dim=-1, keepdim=True)

            image_paths.append(path)
            image_features.append(features.cpu().numpy())
        except Exception as e:
            print(f"Skipping {fname}: {e}")
    measure_time("Image encoding")

    # --- Create FAISS index ---
    image_features_np = torch.cat([torch.from_numpy(f) for f in image_features]).numpy()
    index = faiss.IndexFlatIP(image_features_np.shape[1])  # cosine similarity via normalized dot product
    index = faiss.IndexIDMap2(index)  # to keep track of image paths
    index.add_with_ids(image_features_np, [0, 1,2,3,4,5])

    # --- Save index to disk ---
    faiss.write_index(index, knn_index_path)
    measure_time("FAISS index creation")
    return index

index = get_clip_index()

# --- Encode text query ---
text_tokens = tokenizer([QUERY_TEXT]).to(device)
with torch.no_grad():
    text_features = model.encode_text(text_tokens)
    text_features = text_features / text_features.norm(dim=-1, keepdim=True)
text_vector = text_features.cpu().numpy()
measure_time("Text encoding")

# --- Search ---
scores, indices = index.search(text_vector, TOP_K)
measure_time("Total time for image search")

print(f"\nTop {TOP_K} results for query: '{QUERY_TEXT}':")
for idx, score in zip(indices[0], scores[0]):
    print(f"{image_paths[idx]} (score: {score:.3f})")