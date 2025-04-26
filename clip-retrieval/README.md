[Deprecated, just use anaconda virtual env] undocumented rerequisite:
- install vs build tools (e.g. from VS installer)
- install desktop c++ (e.g. from VS installer)
- install fortran compiler (e.g. from msys2)

# Usage
1. Git clone and install clip-retrieval
``` pip install -e .```
2. Install pip deps
``` pip install -r clip-retrieval/requirements.txt```

# Caveats
1. Use this patch to clip-retrieval - https://github.com/rom1504/clip-retrieval/commit/c2a67dc8f979dfeb39b1edeb777ee85f35a44461  
``` pip install -e . ```
2. Need to set env `os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"` to work around duplicate openmp issue