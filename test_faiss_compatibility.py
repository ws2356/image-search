# This script use the faiss/faiss-cpu package to test the compatibility of the faiss with current environment - including cpu arch, os, and python version.
# It is not meant to be a comprehensive test of all faiss features, but rather a demo to prove that we can create and query an index using the dependency we have in our codebase in the current environment.
import sys
import platform
import faiss
import numpy as np
import tempfile
import os

def main():
    print("Testing faiss-cpu compatibility...\n")
    print(f"OS: {platform.system()} {platform.release()}")
    print(f"Architecture: {platform.machine()}")
    print(f"Python Version: {sys.version.split()[0]}")
    print(f"FAISS Version: {getattr(faiss, '__version__', 'Unknown')}\n")
    
    try:
        # Create random data to mimic embeddings
        d = 512                           # dimension (OpenCLIP ViT-B-32 output dimension)
        nb = 100                          # database size
        nq = 5                            # nb of queries
        
        print(f"Generating {nb} random database vectors and {nq} query vectors of dimension {d}...")
        np.random.seed(1234)              # make reproducible
        xb = np.random.random((nb, d)).astype('float32')
        xq = np.random.random((nq, d)).astype('float32')
        
        # Our application uses IndexFlatIP wrapped in IndexIDMap2
        print("Initializing FAISS index (IndexFlatIP + IndexIDMap2)...")
        index = faiss.IndexFlatIP(d)
        index = faiss.IndexIDMap2(index)
        
        print("Adding vectors with arbitrary IDs to the index...")
        # IDs must be int64 for IndexIDMap2
        ids = np.arange(1000, 1000 + nb).astype('int64') 
        index.add_with_ids(xb, ids)
        
        print(f"Index successfully populated. Total vectors: {index.ntotal}")
        
        print("Executing search query...")
        k = 4                             # find top 4 nearest neighbors
        distances, indices = index.search(xq, k) 
        
        print(f"Search successful! Returned indices matrix shape: {indices.shape}")
        assert indices.shape == (nq, k), "Search result shape mismatch"
        
        # Test serialization (Disk I/O) used by our indexer
        fd, temp_path = tempfile.mkstemp(suffix='.faiss')
        os.close(fd)
        
        print(f"\nTesting index serialization (write/read) to temporary file...")
        faiss.write_index(index, temp_path)
        index_loaded = faiss.read_index(temp_path)
        
        print(f"Index successfully loaded from disk. Loaded total vectors: {index_loaded.ntotal}")
        assert index_loaded.ntotal == index.ntotal, "Loaded index vector count mismatch"
        
        # Clean up
        os.remove(temp_path)
        
        print("\n✅ SUCCESS: All core FAISS operations (Init, Add, Search, I/O) completed without error.")
        
    except Exception as e:
        print(f"\n❌ ERROR: FAISS compatibility test failed!")
        print(f"Exception: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()