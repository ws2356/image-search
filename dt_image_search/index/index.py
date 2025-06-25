import os
import time
import torch
import typing
import open_clip
from PIL import Image
from torchvision import transforms
from tqdm import tqdm
import faiss

def query(index_path: str, query_text: str) -> typing.List[str]:
  pass