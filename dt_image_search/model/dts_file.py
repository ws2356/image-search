class File:
    def __init__(self, id: int, path: str, folder_id: int, clip_index: int = None, status: str = "normal"):
        self.id = id
        self.path = path
        self.folder_id = folder_id
        self.clip_index = clip_index
        self.status = status