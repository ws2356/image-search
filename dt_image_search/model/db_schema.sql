-- folders table
CREATE TABLE IF NOT EXISTS folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT UNIQUE NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- files table
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL,
    folder_id INTEGER NOT NULL,
    clip_index INTEGER,
    status INTEGER NOT NULL DEFAULT 0, -- 0: pending, 1: indexed, 2: removed
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(folder_id) REFERENCES folders(id)
);

-- Optional index
CREATE INDEX IF NOT EXISTS idx_files_folder_status ON files(folder_id, status);
