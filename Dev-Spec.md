# DT Image Search - Dev Spec: React + FastAPI Refactor

## 1. Overall Architecture

The application will be restructured from a monolithic PySide6 desktop application to a decoupled Browser/Server architecture.
- **Frontend**: A React application (Single Page Application) that serves the UI in the browser. It will replace all PyQt components (views, models, controllers).
- **Backend**: A Python 3.10 backend utilizing FastAPI. It will expose a REST API and WebSockets for real-time updates. The core logic of the existing app (OpenCLIP models, FAISS indexing, SQLite WAL database, watchdog filesystem monitoring) will be retained and orchestrated via API endpoints.

### Key Flows
1. **User Interaction**: User interacts with the React frontend (e.g., adds a folder, types a search query).
2. **API Requests**: React app makes HTTP calls to the FastAPI backend.
3. **Backend Processing**:
   - For searching: Queries the FAISS index.
   - For adding folders: Updates SQLite database and spawns background threads (`IndexWorker`) to index images.
4. **Real-Time Updates**:
   - `watchdog` monitors the filesystem for changes.
   - Filesystem events are buffered and processed by `incremental_index_worker`.
   - The backend pushes real-time events (like indexing progress, folder changes) to the frontend via WebSockets.

---

## 2. Frontend Project Structure (React)

The frontend will be a standard React application (e.g., initialized via Vite or Next.js) using TypeScript.

### Structure
```
frontend/
├── package.json
├── src/
│   ├── components/       # Reusable UI components
│   │   ├── MainLayout.tsx          # App shell (split panel)
│   │   ├── SearchInput.tsx         # Text search with debounce/clear
│   │   ├── FolderTreeView.tsx      # Hierarchical folder navigation
│   │   ├── ImageGridView.tsx       # Thumbnail grid
│   │   ├── ImageViewerDialog.tsx   # Full-screen image viewer (zoom, pan, navigate)
│   │   └── AddFolderButton.tsx     # Triggers folder selection
│   ├── hooks/            # Custom React hooks (e.g., useWebSocket, useSearch)
│   ├── services/         # API client layer (Axios/fetch wrappers)
│   │   ├── api.ts        # REST endpoints wrappers
│   │   └── websocket.ts  # WebSocket connection manager
│   ├── store/            # State management (Zustand, Redux, or Context API)
│   ├── App.tsx           # Root component
│   └── index.tsx         # Entry point
```

### State Management
- **App Mode**: `browse` | `search` (controls the main view).
- **Selected Folder**: Currently active folder in the tree.
- **Image List**: Array of images to display in the grid.
- **Viewer State**: Controls the full-screen modal `{ isOpen, currentImage, zoom, list_context }`.
- **Search Query**: Current text in the search box.

---

## 3. Backend Project Structure (FastAPI)

The backend will refactor the existing Python codebase into a modern FastAPI layout.

### Structure
```
backend/
├── requirements.txt           # Production dependencies (torch, open_clip_torch, faiss-cpu, fastapi, uvicorn, watchdog, etc.)
├── pyproject.toml             # Project metadata and configuration
├── app/
│   ├── __init__.py
│   ├── main.py                # FastAPI app initialization and uvicorn entry point
│   ├── config.py              # Configuration and BMContext equivalent
│   ├── api/                   # API Routers
│   │   ├── routes/
│   │   │   ├── folders.py     # Folder CRUD and indexing routes
│   │   │   ├── search.py      # Search routes
│   │   │   ├── images.py      # Image retrieval (thumbnails, raw files)
│   │   │   └── websocket.py   # WebSocket endpoint for real-time events
│   ├── services/              # Core business logic
│   │   ├── search_service.py  # Wrapper for FAISS search logic
│   │   ├── folder_service.py  # Folder management logic
│   │   └── event_bus.py       # Internal event bus (from dts_event_bus.py)
│   ├── db/                    # Database layer
│   │   └── database.py        # SQLite interactions (from dts_db.py)
│   ├── indexing/              # Background indexing tasks
│   │   ├── index_worker.py    # Main batch indexing
│   │   └── incremental_index_worker.py # Watchdog real-time indexer
│   ├── fs/                    # Filesystem monitoring
│   │   └── fs_monitor.py      # Watchdog setup (from bm_fs_monitor.py)
│   └── telemetry/             # OpenTelemetry integration
└── tests/
```

### Key Components to Keep
- **dts_db.py**: Keep the SQLite WAL setup. Abstract it slightly if needed for FastAPI dependency injection.
- **index_worker.py & incremental_index_worker.py**: Maintain the background threading for indexing. Tie them to FastAPI's lifecycle events (`lifespan`).
- **bm_context.py**: Migrate configuration to `pydantic-settings` or keep it as a singleton.

---

## 4. API Endpoints Specification

### REST API

| Method | Endpoint | Description |
|---|---|---|
| **POST** | `/api/search` | Search indexed folders using text query. Returns top-K results. |
| **GET** | `/api/folders` | List all root folders. |
| **POST** | `/api/folders` | Add a new folder to index. |
| **GET** | `/api/folders/{path}/children` | Lazy-load subfolders. |
| **GET** | `/api/folders/{path}/images` | Get images within a folder. |
| **DELETE**| `/api/folders/{folder_id}` | Remove folder from app and index by folder_id. |
| **GET** | `/api/images/{id}` | Get image metadata. |
| **GET** | `/api/images/{id}/thumbnail` | Serve image thumbnail. |
| **GET** | `/api/images/{id}/raw` | Serve raw image file. |
| **GET** | `/api/index/status` | Check the indexing status of folders. |

### WebSockets

| Endpoint | Purpose | Messages |
|---|---|---|
| `ws://<host>/ws/events` | Push real-time events to the frontend. | - `indexing_progress` (folder_id, current, total)<br>- `folder_status_changed`<br>- `fs_event` (file created, deleted, moved) |

---

## 5. Migration Strategy

1. **Backend Initialization**:
   - Set up the FastAPI shell in a new `backend/` directory.
   - Copy over the core AI, DB, and Indexing logic (`model/`, `index/`, `search/`, `fs/`).
   - Create FastAPI routes to wrap the `SearchController` and `BrowseController` logic.
   - Implement the WebSocket handler bridging the internal `event_bus` to connected WS clients.
   - Test endpoints using `pytest` and HTTP clients (Swagger UI).

2. **Frontend Initialization**:
   - Initialize the React project in a new `frontend/` directory.
   - Build out the static UI components (`MainLayout`, `FolderTreeView`, `ImageGridView`).
   - Implement state management for view toggling and component state.

3. **Integration**:
   - Connect the React frontend to the FastAPI backend.
   - Implement data fetching (e.g., using `react-query` or `SWR`).
   - Establish the WebSocket connection for real-time UI updates (progress bars, folder refreshes).
   - Implement lazy loading for thumbnails and folder trees.

4. **Cleanup & Packaging**:
   - Remove PySide6 dependencies and related files (`view/`, `.ui` files, `__main__.py` Qt setup).
   - Update `requirements.txt` to reflect the new backend stack.
   - Create scripts to serve both the frontend (e.g., compiled static assets served via FastAPI or a reverse proxy) and the backend process.