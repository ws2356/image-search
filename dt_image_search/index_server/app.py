# FastAPI app factory for the index server: token-protected API surface,
# token-free /health for the shell's liveness probe, optional static hosting
# of the Vue3 build with SPA history-mode fallback, and the /events WebSocket
# fed by the dts_event_bus bridge.
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, WebSocket
from fastapi.staticfiles import StaticFiles

from dt_image_search.index_server.auth import token_verifier
from dt_image_search.index_server.routes import attach_routes
from dt_image_search.index_server.event_bridge import attach_event_bridge
from dt_image_search.index_server.ws import EventBroker
from dt_image_search.bm_context import BMContext


class SPAStaticFiles(StaticFiles):
    """StaticFiles with a history-mode SPA fallback to index.html."""

    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)
        if response.status_code == 404:
            return await super().get_response("index.html", scope)
        return response


def create_app(ctx: BMContext, token: str, static_dir: str | None = None) -> FastAPI:
    broker = EventBroker(token)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        broker.attach_loop(asyncio.get_running_loop())
        bridge = attach_event_bridge(broker)
        yield
        bridge.dispose()

    app = FastAPI(lifespan=lifespan)
    app.state.ctx = ctx
    app.state.token = token

    verify = token_verifier(token)
    # Routes added later (routes.attach_routes) hang off this protected list;
    # /health stays token-free below.
    app.auth_dependencies = [Depends(verify)]
    attach_routes(app)

    @app.get("/health")
    async def health():
        # Token-free on purpose: the shell probes liveness before it hands
        # the authenticated URL to the web view.
        return {"status": "ok"}

    if static_dir and Path(static_dir).is_dir():
        app.mount("/", SPAStaticFiles(directory=static_dir, html=True), name="webui")

    @app.websocket("/events")
    async def events(websocket: WebSocket):
        await broker.connect(websocket)

    return app
