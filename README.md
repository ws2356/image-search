# TODO
1. Package for different architectures
2. Show a tree view on left panel
3. Create a clip index for any directory in the trees, based on the folder size
4. Fix following warning: OMP: Error #15: Initializing libomp140.x86_64.dll, but found libiomp5md.dll already initialized.
OMP: Hint This means that multiple copies of the OpenMP runtime have been linked into the program. That is dangerous, since it can degrade performance or cause incorrect results. The best thing to do is to ensure that only a single OpenMP runtime is linked into the process, e.g. by avoiding static linking of the OpenMP runtime in any library. As an unsafe, unsupported, undocumented workaround you can set the environment variable KMP_DUPLICATE_LIB_OK=TRUE to allow the program to continue to execute, but that may cause crashes or silently produce incorrect results. For more information, please see http://openmp.llvm.org/
5. Build index async: add a status field to folder (0: pending, 1: traversed, 2: indexed)
6. Monitor fs to automatically adding new files to index
7. Prevent model loading code from depending on web request
8. TODO: download pretrained model
9. Index on launch
10. debug on TestWin vm