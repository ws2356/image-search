-- folders table
CREATE TABLE IF NOT EXISTS folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT UNIQUE NOT NULL,
    status INTEGER NOT NULL DEFAULT 0, -- 0: scanning, 1: indexing, 2: indexed
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

-- app_config table
CREATE TABLE IF NOT EXISTS app_config (
    key CHAR(128) NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

-- Optional index
CREATE INDEX IF NOT EXISTS idx_files_folder_status ON files(folder_id, status);

-- Unique constraint(folder_id + path) on files table
CREATE UNIQUE INDEX IF NOT EXISTS idx_files_folder_path ON files(folder_id, path);