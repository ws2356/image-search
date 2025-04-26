from sys import argv
import faiss
import numpy as np
import clip
import torch
from IPython.display import Image, display
from pathlib import Path
import pandas as pd
from PIL import Image as PILImage
import os

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

data_dir = Path("clip-retrieval\\embeddings\\metadata")
df = pd.concat(
    pd.read_parquet(parquet_file)
    for parquet_file in data_dir.glob('*.parquet')
)
image_list = df["image_path"].tolist()


ind = faiss.read_index("clip-retrieval\\knn.index")

device = "cuda" if torch.cuda.is_available() else "cpu"
model, preprocess = clip.load("ViT-B/32", device=device, jit=False)


text = argv[1] if len(argv) > 1 else "a photo of a cat"
print("query : %s" % text)

text_tokens = clip.tokenize([text], truncate=True)

text_features = model.encode_text(text_tokens.to(device))
text_features /= text_features.norm(dim=-1, keepdim=True)
text_embeddings = text_features.cpu().detach().numpy().astype('float32')

D, I = ind.search(text_embeddings, 1)
print("results :")
for d, i in zip(D[0], I[0]):
  print("similarity=", d)
  print(i)

print("image_path=", image_list[i])
pil_img = PILImage.open(image_list[i])
pil_img.show()