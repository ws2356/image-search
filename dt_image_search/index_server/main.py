# Entrypoint for the index server process: runs the core indexing/search
# logic headlessly as a child of the shell, announcing its bound port via the
# DTS_READY stdout handshake once uvicorn has started.
import argparse
import threading
import time

from dt_image_search.tools.process_env import setup_process_env


def run_server(token: str, static_dir: str | None = None) -> None:
    setup_process_env()

    from pc_common.model.feature_flags import initialize_feature_flags
    from dt_image_search.bm_context import get_context, setup_model_cache
    from dt_image_search.index_server.app import create_app

    initialize_feature_flags()
    ctx = get_context()
    setup_model_cache(ctx=ctx)

    import uvicorn

    app = create_app(ctx, token, static_dir)
    config = uvicorn.Config(app, host="127.0.0.1", port=0, log_level="warning")
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    deadline = time.time() + 60
    while not server.started and time.time() < deadline:
        time.sleep(0.05)
    if not server.started:
        raise RuntimeError("index server failed to start")
    port = server.servers[0].sockets[0].getsockname()[1]
    print(f"DTS_READY {port}", flush=True)

    thread.join()


def main() -> None:
    parser = argparse.ArgumentParser(description="AuSearch index server")
    parser.add_argument("--auth-token", required=True, help="One-time token shared with the shell/webui")
    parser.add_argument("--static-dir", default=None, help="Directory of the webui build to serve")
    args = parser.parse_args()
    run_server(token=args.auth_token, static_dir=args.static_dir)


if __name__ == "__main__":
    main()
