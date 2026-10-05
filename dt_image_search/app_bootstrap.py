# Shared indexing pipeline lifecycle: one startup and one shutdown sequence
# used by both the legacy Qt app and the Qt-free index server process (DRY).
from dt_image_search.bm_context import BMContext


def init_indexing_pipeline(ctx: BMContext, skip_model_init: bool = False) -> None:
    """Start the model downloader, index system, incremental + bulk index
    workers and the filesystem watcher — in the legacy startup order."""
    from dt_image_search.index.dts_model_downloader import init as model_downloader_init
    from dt_image_search.index.dts_index import init as index_init

    if not skip_model_init:
        model_downloader_init(ctx)  # Start model downloader if needed
        index_init(ctx)             # Initialize the index system

    from dt_image_search.index.incremental_index_worker import init_incremental_index_workers
    from dt_image_search.index.index_worker import init_index_workers
    from dt_image_search.fs.bm_fs_monitor import start_watch

    init_incremental_index_workers(ctx)
    init_index_workers(ctx)
    start_watch(ctx)


def deinit_indexing_pipeline() -> None:
    """Stop the filesystem watcher and all index workers — reverse order."""
    from dt_image_search.fs.bm_fs_monitor import stop_watch
    from dt_image_search.index.incremental_index_worker import deinit_incremental_index_workers
    from dt_image_search.index.index_worker import deinit_index_workers

    stop_watch()
    deinit_incremental_index_workers()
    deinit_index_workers()
