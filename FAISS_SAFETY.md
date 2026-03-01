# FAISS Safety Guidelines (Authored by opencode)

To prevent segmentation faults and ensure the stability of FAISS operations in this project, follow these guidelines:

## 1. Memory Layout (Contiguity)
FAISS requires input arrays to be **C-contiguous**. Always ensure your numpy arrays are contiguous before passing them to `index.search()` or `index.add()`.
```python
if not array.flags['C_CONTIGUOUS']:
    array = np.ascontiguousarray(array)
```

## 2. Data Types
Most FAISS indices (including `IndexFlatIP` and `IndexIDMap2` used here) require **float32** for vectors and **int64** for IDs.
```python
features = features.astype(np.float32)
ids = ids.astype(np.int64)
```

## 3. Thread Safety & Concurrency
FAISS indices are **not thread-safe** for concurrent read/write operations. 
- Multiple threads can **read** (search) simultaneously.
- A **write** operation (add/remove) must have exclusive access.
- Use a `threading.Lock` per index file to synchronize access.

## 4. Vector Normalization
When using `IndexFlatIP` for cosine similarity, ensure all vectors are normalized to unit length.
```python
features = features / (np.linalg.norm(features, axis=-1, keepdims=True) + 1e-10)
```
*Note: Adding a small epsilon (1e-10) prevents division by zero for empty/black images.*

## 5. Dimension Consistency
Ensure the dimension of input vectors matches the dimension the index was initialized with.
```python
dim = model.visual.output_dim
index = faiss.IndexFlatIP(dim)
```

## 6. Error Handling
Always wrap FAISS operations in try-except blocks to catch potential runtime errors, although segmentation faults may still bypass Python's exception handling.
