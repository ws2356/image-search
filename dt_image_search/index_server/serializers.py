# Wire serialization for index server API responses.
# Contract: every id is a string on the wire (opaque to clients).
from dt_image_search.model.dts_file import File
from dt_image_search.model.dts_folder import Folder


def folder_to_dict(folder: Folder) -> dict:
    return {
        "id": str(folder.id),
        "path": folder.path,
        "status": folder.status,
        "added_at": folder.added_at,
    }


def file_to_dict(file: File) -> dict:
    return {
        "id": str(file.id),
        "path": file.path,
        "folder_id": str(file.folder_id),
        "status": file.status,
    }


def search_result_to_dict(file: File, score: float) -> dict:
    return {
        "id": str(file.id),
        "path": file.path,
        "folder_id": str(file.folder_id),
        "score": score,
    }
