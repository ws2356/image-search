# HTTP API routes for the index server.
# Thin delegation layer: all business logic lives in the Qt-free services
# (folder_service / search_service) and dts_db; handlers are async and wrap
# sync core calls with asyncio.to_thread (see 2026-10-04-asyncio-migration-notes.md).
import asyncio
import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator

from dt_image_search.browse.folder_service import register_folder, watch_and_index, remove_folder, reindex_folder
from dt_image_search.index.dts_index import is_image_file
from dt_image_search.index_server.media import ThumbnailCache, FileGoneError
from dt_image_search.model.dts_db import (
    create_db_conn,
    get_all_folders,
    get_file_by_id,
    get_folder_by_id,
    get_subfolders,
    get_direct_child_files,
)
from dt_image_search.search.search_service import search_folders, ModelNotReadyError
from dt_image_search.index_server.serializers import (
    folder_to_dict,
    file_to_dict,
    search_result_to_dict,
)
from dt_image_search.tools.dts_util import is_same_folder_path
from pc_common.model.dts_fs import get_app_data_path
from fastapi.responses import FileResponse


class FolderAddRequest(BaseModel):
    path: str

    @field_validator("path")
    @classmethod
    def path_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("path must not be empty")
        return v


def _folder_by_id(folder_id: int):
    with create_db_conn() as conn:
        return get_folder_by_id(conn, folder_id)


def _list_folders():
    with create_db_conn() as conn:
        return get_all_folders(conn)


def _browse_payload(folder, path: str | None):
    root = path if path else folder.path
    with create_db_conn() as conn:
        subfolders = [
            f for f in get_subfolders(conn, root)
            if not is_same_folder_path(f.path, folder.path)
        ]
        files = [
            f for f in get_direct_child_files(conn, root)
            if f.folder_id == folder.id and is_image_file(f.path)
        ]
    return subfolders, files


def _file_by_id(file_id: int):
    with create_db_conn() as conn:
        return get_file_by_id(conn, file_id)


def attach_routes(app) -> None:
    protected = APIRouter(dependencies=app.auth_dependencies)
    app.state.thumbnail_cache = None  # built lazily on first /thumb call

    @protected.get("/ping")
    async def ping():
        return {"ok": True}

    @protected.get("/folders")
    async def list_folders(request: Request):
        folders = await asyncio.to_thread(_list_folders)
        return {"folders": [folder_to_dict(f) for f in folders]}

    @protected.post("/folders")
    async def add_folder(request: Request, body: FolderAddRequest):
        target = Path(body.path)
        if not await asyncio.to_thread(target.is_dir):
            raise HTTPException(status_code=400, detail="path is not a directory")
        ctx = request.app.state.ctx
        folder, created = await asyncio.to_thread(register_folder, ctx, body.path)
        if folder is None:
            raise HTTPException(status_code=500, detail="failed to register folder")
        if created:
            await asyncio.to_thread(watch_and_index, ctx, folder)
        return JSONResponse(folder_to_dict(folder), status_code=201 if created else 200)

    @protected.delete("/folders/{folder_id}")
    async def delete_folder_route(request: Request, folder_id: int):
        folder = await asyncio.to_thread(_folder_by_id, folder_id)
        if folder is None:
            raise HTTPException(status_code=404, detail="folder not found")
        ctx = request.app.state.ctx
        await asyncio.to_thread(remove_folder, ctx, folder.path)
        return Response(status_code=204)

    @protected.post("/folders/{folder_id}/reindex")
    async def reindex_folder_route(request: Request, folder_id: int):
        folder = await asyncio.to_thread(_folder_by_id, folder_id)
        if folder is None:
            raise HTTPException(status_code=404, detail="folder not found")
        if folder.status == 2:
            return folder_to_dict(folder)
        ctx = request.app.state.ctx
        await asyncio.to_thread(reindex_folder, ctx, folder)
        return JSONResponse(folder_to_dict(folder), status_code=202)

    @protected.get("/search")
    async def search_route(request: Request, q: str = Query(min_length=1), limit: int | None = Query(default=None, gt=0)):
        ctx = request.app.state.ctx
        try:
            results = await asyncio.to_thread(search_folders, ctx, q)
        except ModelNotReadyError as e:
            raise HTTPException(status_code=503, detail={"model_state": e.state})
        if limit is not None:
            results = results[:limit]
        return {"results": [search_result_to_dict(f, s) for f, s in results]}

    @protected.get("/browse")
    async def browse_route(request: Request, folder_id: int, path: str | None = Query(default=None)):
        folder = await asyncio.to_thread(_folder_by_id, folder_id)
        if folder is None:
            raise HTTPException(status_code=404, detail="folder not found")
        subfolders, files = await asyncio.to_thread(_browse_payload, folder, path)
        return {
            "folder": folder_to_dict(folder),
            "subfolders": [folder_to_dict(f) for f in subfolders],
            "files": [file_to_dict(f) for f in files],
        }

    @protected.get("/thumb/{file_id}")
    async def thumb_route(request: Request, file_id: int):
        file = await asyncio.to_thread(_file_by_id, file_id)
        if file is None:
            raise HTTPException(status_code=404, detail="file not found")
        cache = request.app.state.thumbnail_cache
        if cache is None:
            cache = ThumbnailCache(cache_dir=str(get_app_data_path() / "thumb_cache"))
            request.app.state.thumbnail_cache = cache
        try:
            thumb_path = await asyncio.to_thread(cache.get_or_build, file)
        except FileGoneError:
            raise HTTPException(status_code=404, detail="source image is gone")
        return FileResponse(thumb_path, media_type="image/jpeg")

    @protected.get("/file/{file_id}")
    async def file_route(request: Request, file_id: int):
        file = await asyncio.to_thread(_file_by_id, file_id)
        if file is None:
            raise HTTPException(status_code=404, detail="file not found")
        if not await asyncio.to_thread(os.path.isfile, file.path):
            raise HTTPException(status_code=404, detail="source image is gone")
        return FileResponse(file.path)

    app.include_router(protected)
