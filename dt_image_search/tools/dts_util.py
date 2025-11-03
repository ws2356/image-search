def normalized_folder_path(folder_path: str) -> str:
    # Append a trailing slash '/' if not already existing
    if not folder_path.endswith('/'):
        folder_path += '/'
    return folder_path

def back_slash_to_forward_slash(path: str) -> str:
    return path.replace('\\', '/')

def is_same_folder_path(path1: str, path2: str) -> bool:
    if not path1:
        return not path2
    if not path2:
        return not path1
    return normalized_folder_path(back_slash_to_forward_slash(path1)) == normalized_folder_path(back_slash_to_forward_slash(path2))