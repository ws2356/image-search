def normalized_folder_path(folder_path: str) -> str:
    # Append a trailing slash '/' if not already existing
    if not folder_path.endswith('/'):
        folder_path += '/'
    return folder_path

def back_slash_to_forward_slash(path: str) -> str:
    return path.replace('\\', '/')