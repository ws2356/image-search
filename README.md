# TODO
1. Package for different architectures
2. Show a tree view on left panel
3. Create a clip index for any directory in the trees, based on the folder size
4. Fix following warning: OMP: Error #15: Initializing libomp140.x86_64.dll, but found libiomp5md.dll already initialized.
OMP: Hint This means that multiple copies of the OpenMP runtime have been linked into the program. That is dangerous, since it can degrade performance or cause incorrect results. The best thing to do is to ensure that only a single OpenMP runtime is linked into the process, e.g. by avoiding static linking of the OpenMP runtime in any library. As an unsafe, unsupported, undocumented workaround you can set the environment variable KMP_DUPLICATE_LIB_OK=TRUE to allow the program to continue to execute, but that may cause crashes or silently produce incorrect results. For more information, please see http://openmp.llvm.org/
5. Build index async: add a status field to folder (0: pending, 1: traversed, 2: indexed)
6. Monitor fs to automatically adding new files to index
<!-- 7. Prevent model loading code from depending on web request -->
<!-- 8. TODO: download pretrained model -->
<!-- 9. Index on launch -->
<!-- 10. debug on TestWin vm -->
11. Microsoft Visual C++ Redistributable is not installed, this may lead to the DLL load failure.
                 It can be downloaded at https://aka.ms/vs/16/release/vc_redist.x64.exe
12. Resource requirements: 8G memory
13. `<TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.22621.0" />` determine the version range
14. excessive otel logs...
15. subprocess is also creating window(s)
16. subprocess killed for unknown reason:
```
INFO:imagesearch_client: at : Resuming indexing for folder: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000000.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000527 seconds (shallow)
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000001.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000348 seconds (shallow)
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000002.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000307 seconds (shallow)
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000003.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000309 seconds (shallow)
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000004.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000301 seconds (shallow)
DEBUG:imagesearch_client: at : Inserting file: C:/Users/ws2356/Downloads/image-dataset/image-dataset/00000\000000005.jpg into folder ID: 1
DEBUG:imagesearch_client:perf at : insert_file took 0.000296 seconds (shallow)
DEBUG:imagesearch_client:perf at : build_index took 0.000004 seconds (shallow)
INFO:imagesearch_client: at : Start building index for folder ID 1 at C:\Users\ws2356\AppData\Roaming\DTImageSearch/1.faiss
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): huggingface.co:443
DEBUG:urllib3.connectionpool:https://huggingface.co:443 "HEAD /laion/CLIP-ViT-B-32-laion2B-s34B-b79K/resolve/main/open_clip_pytorch_model.bin HTTP/1.1" 302 0
INFO:root:Loading pretrained ViT-B-32 weights (laion2b_s34b_b79k).
ERROR:imagesearch_client:embedding at : Error processing batch 0: A process in the process pool was terminated abruptly while the future was running or pending.
WARNING:imagesearch_client:embedding at : No valid images to add to index
DEBUG:imagesearch_client:perf at : add_to_index took 20.040357 seconds (shallow)
DEBUG:imagesearch_client: at : Index progress: 6/6 files processed
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/metrics HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/logs HTTP/1.1" 200 2
ERROR:imagesearch_client:embedding at : Error processing batch 0:
WARNING:imagesearch_client:embedding at : No valid images to add to index
DEBUG:imagesearch_client:perf at : add_to_index took 60.021945 seconds (shallow)
DEBUG:imagesearch_client: at : Index progress: 6/6 files processed
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): otel.wansong.vip:443
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): otel.wansong.vip:443
```
17. Empty log/metric request?
```
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): otel.wansong.vip:443
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): otel.wansong.vip:443
DEBUG:urllib3.connectionpool:Starting new HTTPS connection (1): otel.wansong.vip:443
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/traces HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/metrics HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/logs HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/metrics HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/logs HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/metrics HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/logs HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/metrics HTTP/1.1" 200 2
DEBUG:urllib3.connectionpool:https://otel.wansong.vip:443 "POST /v1/logs HTTP/1.1" 200 2
```
18. Logs are not batched