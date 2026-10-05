# FastAPI app factory for the index server: token-protected API surface,
# token-free /health for the shell's liveness probe, optional static hosting
# of the Vue3 build with SPA history-mode fallback, and the /events WebSocket
# fed by the dts_event_bus bridge.
import asyncio
import secrets
import urllib.parse
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, WebSocket
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import Response

from dt_image_search.index_server.auth import token_verifier
from dt_image_search.index_server.routes import attach_routes
from dt_image_search.index_server.event_bridge import attach_event_bridge
from dt_image_search.index_server.ws import EventBroker
from dt_image_search.bm_context import BMContext


class SPAStaticFiles(StaticFiles):
    """StaticFiles with a history-mode SPA fallback to index.html.

    The SPA entry (index.html — direct or via fallback) is token-gated via
    the auth query param. Hashed asset bundles are not user data and stay
    reachable so plain <script src> tags can load without per-URL tokens.
    """

    def __init__(self, directory: str, token: str):
        super().__init__(directory=directory, html=True)
        self._token = token

    def _authorized(self, scope) -> bool:
        query_string = scope.get("query_string", b"")
        params = urllib.parse.parse_qs(query_string.decode("latin-1"))
        supplied = (params.get("auth") or [None])[0]
        return bool(supplied) and secrets.compare_digest(supplied, self._token)

    _SPA_ENTRY_PATHS = ("", ".", "index.html", "./index.html")

    async def get_response(self, path: str, scope):
        if path in self._SPA_ENTRY_PATHS and not self._authorized(scope):
            return Response(status_code=401, content="unauthorized")
        try:
            response = await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code != 404:
                raise
            if not self._authorized(scope):
                return Response(status_code=401, content="unauthorized")
            return await super().get_response("index.html", scope)
        if response.status_code == 404:
            if not self._authorized(scope):
                return Response(status_code=401, content="unauthorized")
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

    # The /events WebSocket MUST be registered before the catch-all SPA mount
    # (a Mount matches any scope type and would otherwise swallow the
    # handshake whenever the static UI is served — i.e. always in production).
    @app.websocket("/events")
    async def events(websocket: WebSocket):
        await broker.connect(websocket)

    if static_dir and Path(static_dir).is_dir():
        app.mount("/", SPAStaticFiles(directory=static_dir, token=token), name="webui")

    return app
