# Bundle entry: the Qt-free index server sidecar (launched as a sibling
# executable by the shell when frozen).
if __name__ == "__main__":
    from multiprocessing import freeze_support

    # PyInstaller worker invocations must be diverted before CLI parsing/imports.
    freeze_support()
    from dt_image_search.index_server.main import main

    main()
