[Deprecated, just use anaconda virtual env] undocumented rerequisite:
- install vs build tools (e.g. from VS installer)
- install desktop c++ (e.g. from VS installer)
- install fortran compiler (e.g. from msys2)

# Usage
1. Git clone and install clip-retrieval
``` pip install -e .```
2. Install pip deps
``` pip install -r clip-retrieval/requirements.txt```
3. Reinstall faiss-cpu (refer to caveat #2)
 `pip uninstall faiss-cpu; conda install faiss-cpu`

# Caveats
1. Use this patch to clip-retrieval - https://github.com/rom1504/clip-retrieval/commit/c2a67dc8f979dfeb39b1edeb777ee85f35a44461  
``` pip install -e . ```
2. Reinstall `faiss-cpu` using `pip uninstall faiss-cpu; conda install faiss-cpu`. On my machine, that would replace faiss-cpu==1.10.0 with faiss-cpu==1.9.0, which would fix the OpenMP runtime version conflict error
    > OMP: Hint This means that multiple copies of the OpenMP runtime have been linked into the program. That is dangerous, since it can degrade performance or cause incorrect results. The best thing to do is to ensure that only a single OpenMP runtime is linked into the process, e.g. by avoiding static linking of the OpenMP runtime in any library. As an unsafe, unsupported, undocumented workaround you can set the environment variable KMP_DUPLICATE_LIB_OK=TRUE to allow the program to continue to execute, but that may cause crashes or silently produce incorrect results. For more information, please see http://openmp.llvm.org/
3. [Deprecated, prefer #2] Need to set env `os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"` to work around duplicate openmp issue
4. Need to install ray otherwise img2dataset will fail silently
5. If img2dataset still fails with #4, consider this patch - https://github.com/ws2356/img2dataset/tree/ws2356/customize_base