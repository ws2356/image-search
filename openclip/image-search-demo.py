import os
import torch
import open_clip
from PIL import Image
from torchvision import transforms
from tqdm import tqdm
import faiss

import faulthandler; faulthandler.enable()

# --- Config ---
IMAGE_FOLDER = "../image-dataset/00000"
QUERY_TEXT = "A bowl of noodles"
TOP_K = 5

# --- Load model ---
device = "cuda" if torch.cuda.is_available() else "cpu"
print("before loading model")
model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
print("after loading model")
tokenizer = open_clip.get_tokenizer('ViT-B-32')
model = model.to(device).eval()

# --- Encode images ---
image_paths = []
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

# --- Create FAISS index ---
image_features_np = torch.cat([torch.from_numpy(f) for f in image_features]).numpy()
index = faiss.IndexFlatIP(image_features_np.shape[1])  # cosine similarity via normalized dot product
index.add(image_features_np)

# --- Encode text query ---
text_tokens = tokenizer([QUERY_TEXT]).to(device)
with torch.no_grad():
    text_features = model.encode_text(text_tokens)
    text_features = text_features / text_features.norm(dim=-1, keepdim=True)
text_vector = text_features.cpu().numpy()

# --- Search ---
scores, indices = index.search(text_vector, TOP_K)
print(f"\nTop {TOP_K} results for query: '{QUERY_TEXT}':\n")
for idx, score in zip(indices[0], scores[0]):
    print(f"{image_paths[idx]} (score: {score:.3f})")
