# FastAPI app factory for the index server: token-protected API surface,
# token-free /health for the shell's liveness probe, and optional static
# hosting of the Vue3 build with SPA history-mode fallback.
from pathlib import Path

from fastapi import APIRouter, Depends, FastAPI
from fastapi.staticfiles import StaticFiles

from dt_image_search.index_server.auth import token_verifier
from dt_image_search.bm_context import BMContext


class SPAStaticFiles(StaticFiles):
    """StaticFiles with a history-mode SPA fallback to index.html."""

    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)
        if response.status_code == 404:
            return await super().get_response("index.html", scope)
        return response


def create_app(ctx: BMContext, token: str, static_dir: str | None = None) -> FastAPI:
    app = FastAPI()
    app.state.ctx = ctx
    app.state.token = token

    verify = token_verifier(token)
    protected = APIRouter(dependencies=[Depends(verify)])

    @app.get("/health")
    async def health():
        # Token-free on purpose: the shell probes liveness before it hands
        # the authenticated URL to the web view.
        return {"status": "ok"}

    @protected.get("/ping")
    async def ping():
        return {"ok": True}

    app.include_router(protected)

    if static_dir and Path(static_dir).is_dir():
        app.mount("/", SPAStaticFiles(directory=static_dir, html=True), name="webui")

    return app
