# Entrypoint for the index server process: runs the core indexing/search
# logic headlessly as a child of the shell, announcing its bound port via the
# DTS_READY stdout handshake once uvicorn has started. Shares the indexing
# pipeline startup/cleanup sequence with the legacy Qt app (app_bootstrap).
import argparse
import signal
import threading
import time
from pathlib import Path

from dt_image_search.tools.process_env import setup_process_env

_WEBUI_DIST = Path(__file__).resolve().parent.parent / "webui" / "dist"


def default_static_dir() -> str | None:
    """Serve the built web UI when it exists (packaged/dev runs)."""
    return str(_WEBUI_DIST) if _WEBUI_DIST.is_dir() else None


def run_server(token: str, static_dir: str | None = None, skip_model_init: bool = False) -> None:
    setup_process_env()

    from pc_common.model.feature_flags import initialize_feature_flags
    from dt_image_search.bm_context import get_context, setup_model_cache
    from dt_image_search.app_bootstrap import init_indexing_pipeline, deinit_indexing_pipeline
    from dt_image_search.index_server.app import create_app

    initialize_feature_flags()
    ctx = get_context()
    setup_model_cache(ctx=ctx)
    init_indexing_pipeline(ctx, skip_model_init=skip_model_init)

    import uvicorn

    app = create_app(ctx, token, static_dir)
    config = uvicorn.Config(app, host="127.0.0.1", port=0, log_level="warning")
    server = uvicorn.Server(config)

    def request_shutdown(signum, frame):
        server.should_exit = True

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, request_shutdown)

    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    deadline = time.time() + 60
    while not server.started and time.time() < deadline:
        time.sleep(0.05)
    if not server.started:
        deinit_indexing_pipeline()
        raise RuntimeError("index server failed to start")
    port = server.servers[0].sockets[0].getsockname()[1]
    print(f"DTS_READY {port}", flush=True)

    thread.join()
    deinit_indexing_pipeline()


def main() -> None:
    parser = argparse.ArgumentParser(description="AuSearch index server")
    parser.add_argument("--auth-token", required=True, help="One-time token shared with the shell/webui")
    parser.add_argument("--static-dir", default=None, help="Directory of the webui build to serve")
    parser.add_argument("--skip-model-init", action="store_true", help="Testing switch: skip model downloader/preload")
    args = parser.parse_args()
    run_server(token=args.auth_token, static_dir=args.static_dir or default_static_dir(), skip_model_init=args.skip_model_init)


if __name__ == "__main__":
    main()
