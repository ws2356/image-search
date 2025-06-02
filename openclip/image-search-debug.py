import open_clip
import faiss

# --- Load model ---
model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
print("Model loaded successfully.")