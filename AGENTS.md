# Image Search Agent Guidelines

Welcome to the `image-search` repository. This document outlines the architectural patterns, coding styles, and commands necessary to operate within this codebase. Please adhere to these guidelines when suggesting or implementing changes.

## 1. Tech Stack & Environment
- **Language**: Python 3.10.
- **UI Framework**: PySide6 (Qt for Python). UI layouts are often defined in `.ui` files and compiled.
- **Core AI**: PyTorch, OpenCLIP, and FAISS for image embeddings and similarity search.
- **Database**: SQLite (via `sqlite3`) with Write-Ahead Logging (WAL) for concurrency.
- **Dependencies**: Listed in `requirements.txt` and `requirements-dev.txt` (or `environment.yml` for conda).

## 2. Development Commands
- **Build / Package**: Run `./package.sh` which executes `rm -rf ./build ./dist && pyinstaller DTImageSearch.spec`.
- **Run Application**: Usually executed from the root via `python dt_image_search/main.py` or `python -m dt_image_search`.
- **Testing**: There is no established pytest suite yet, but individual test scripts like `test_exception_handlers.py` can be executed directly via `python test_exception_handlers.py`. Use standard Python `unittest` or `pytest` paradigms for new tests.

## 3. Architecture & State Management
- **Global Context**: A singleton `BMContext` object is passed throughout the app to manage global configuration, model versions, and environment-specific paths. Use it rather than declaring new global variables.
- **UI Architecture**: Follows Qt's Model/View architecture (e.g., `QAbstractListModel` for image lists).
- **Concurrency**: Background tasks (indexing, searching) run in `threading.Thread` to keep the UI responsive.
  - Thread safety must be maintained using `threading.Lock` and `threading.RLock`.
  - Never update the UI directly from a background thread.
- **Communication**: A custom Event Bus (`dts_event_bus.py`) provides a decoupled pub/sub mechanism for component communication (e.g., UI notifying background workers).

## 4. Code Style & Naming Conventions
- **Classes**: `PascalCase` (e.g., `IndexWorker`, `SearchController`).
- **Functions & Methods**: `snake_case` (e.g., `create_db_conn`, `update_folder_status`).
- **Variables**: `snake_case`.
- **Private Members**: Prefixed with a single underscore (e.g., `_run_impl`, `_is_stopped`).
- **Type Hints**: Always use standard Python type hinting for function signatures and class properties.

## 5. Imports and Paths
- **Imports**: Prefer **absolute imports** starting from the package root (e.g., `from dt_image_search.model.dts_db import ...`).
- **Path Manipulation**: Use `pathlib.Path`.
- **Path Storage**: All file paths are normalized to use **forward slashes (`/`)** for cross-platform consistency, especially before being inserted into the database.

## 6. Error Handling & Telemetry
- **Standard Handling**: Use `try...except...finally` blocks. Handle specific exceptions rather than broad `Exception` where possible.
- **Telemetry**: Uses OpenTelemetry for structured logging and metrics.
  - **Do NOT use `print()` or standard `logging` module.**
  - Always import and use the centralized log function: `from dt_image_search.telemetry.telemetry_client import log`.
- **Performance Profiling**: Critical functions are often wrapped with a custom `@perffunc` decorator for execution time monitoring.

## 7. Database Operations
- **SQL Execution**: Always use parameterized queries `(?, ?)` for security and stability.
- **Transactions**: Explicit `conn.commit()` calls must follow write operations.
- **Row Access**: The project uses `conn.row_factory = sqlite3.Row` to allow dictionary-like column access by name. Do not rely on tuple indexing unless strictly necessary.
- **Concurrency**: `PRAGMA journal_mode=WAL;` is enabled to resolve multi-writer conflicts. Keep DB connections short-lived or thread-local if writing heavily.
