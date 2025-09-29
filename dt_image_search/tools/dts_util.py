def normalized_folder_path(folder_path: str) -> str:
    # Append a trailing slash '/' if not already existing
    if not folder_path.endswith('/'):
        folder_path += '/'
    return folder_path