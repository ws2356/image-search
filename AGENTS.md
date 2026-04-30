# Image Search Agent Guidelines

Welcome to the `image-search` repository. This document outlines the architectural patterns, coding styles, and commands necessary to operate within this codebase. Please adhere to these guidelines when suggesting or implementing changes.

## 1. Tech Stack & Environment
- **Language**: Python 3.10.
- **UI Framework**: PySide6 (Qt for Python). UI layouts are often defined in `.ui` files and compiled.
- **Core AI**: PyTorch, OpenCLIP, and FAISS for image embeddings and similarity search.
- **Database**: SQLite (via `sqlite3`) with Write-Ahead Logging (WAL) for concurrency.
- **Dependencies**: Listed in `requirements.txt` and `requirements-dev.txt` (or `environment.yml` for conda).
- **Set up iOS Dev Environment**:
  - Use rbenv: brew install rbenv ruby-build

## 2. Development Commands
- **Package**: Run `dt_image_search/scripts/build_pyinstaller.sh --distpath pyinstaller-dist` to create a packaged app bundle.
- **Package DMG**: Run `dt_image_search/scripts/package_dmg.sh  --app-path pyinstaller-dist/AuSearch.app` to create a standalone application bundle (macOS DMG in this case).
- **Package DMG and notarize**: Run `dt_image_search/scripts/distribute_dmg.sh  --app-path pyinstaller-dist/AuSearch.app` to create a standalone application bundle (macOS DMG) and notarize it.
- **Package MSIX**: Run `powershell dt_image_search/scripts/package_msix.ps1 && powershell dt_image_search/scripts/codesign.ps1` to create msix for Windows.
- **iOS app build & distribution**: See `mobile/ios/fastlane/README.md` for Fastlane commands to build and upload the iOS companion app to App Store Connect. Fastlane prefers App Store Connect API key auth via `API_KEY_ID` and `API_KEY_FILE_PATH` in `mobile/ios/fastlane/.env.credential`; `API_KEY_ISSUER_ID` is optional for individual keys. Manual signing uses `IOS_CODE_SIGN_IDENTITY` and, when `IOS_SIGNING_STYLE=manual`, `IOS_PROVISIONING_PROFILE_SPECIFIER` from `mobile/ios/fastlane/.env`.
- **iOS snapshot tests**: Run `cd mobile/ios && scripts/run_snapshot_tests.sh test` to assert the committed launch/home/transfer/completion snapshots on the configured simulator devices. Run `cd mobile/ios && scripts/run_snapshot_tests.sh record` to refresh the baselines, then `cd mobile/ios && scripts/export_snapshot_marketing_assets.sh` to copy the committed PNGs into `mobile/ios/build/marketing-screenshots/`. The export step flattens screenshots onto a white matte and removes the alpha channel so App Store Connect accepts them. Snapshot filenames include page, device model, and language, e.g. `launch-splash_iPhone-17-Pro-Max_en-US.png`.
- **Run Application**: Usually executed from the root via `python dt_image_search/main.py` or `python -m dt_image_search`.
- **Testing**: There is no established pytest suite yet, but individual test scripts like `test_exception_handlers.py` can be executed directly via `python test_exception_handlers.py`. Use standard Python `unittest` or `pytest` paradigms for new tests.


## 3. Architecture & State Management
- **Global Context**: A singleton `BMContext` object is passed throughout the app to manage global configuration, model versions, and environment-specific paths. Use it rather than declaring new global variables.
- **UI Architecture**: Follows Qt's Model/View architecture (e.g., `QAbstractListModel` for image lists).
- **Concurrency**: Background tasks (indexing, searching) run in `threading.Thread` to keep the UI responsive.
  - Thread safety must be maintained using `threading.Lock` and `threading.RLock`.
  - Never update the UI directly from a background thread.
- **Communication**: A custom Event Bus (`dts_event_bus.py`) provides a decoupled pub/sub mechanism for component communication (e.g., UI notifying background workers).

## 4. Code Rules
- **Separation of Concerns**: UI code should not contain business logic. Business logic should be in separate controller or worker classes. Each file should have a clear and often singular responsibility.
- **Use asyncio**: The existing codebase is primarily synchronous, but new code should prefer `asyncio` for any I/O-bound operations (e.g., database access, file I/O) to improve responsiveness and scalability. Use `async def` and `await` as needed.
- **Concurrency**: Ensure correctness under concurrent conditions. Even for local http/websocket servers, prepare for potential concurrent requests.
- **Design Patterns**: Use approriate design patterns, e.g. DI, MVC, MVVM, State Machine, etc. where they fit naturally.
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
- **Telemetry**: Uses OpenTelemetry for structured logging, tracing and metrics.
  - **Do NOT use `print()` or standard `logging` module.**
  - Always import and use the centralized log function: `from dt_image_search.telemetry.telemetry_client import log`.
  - **Span-First approach**: Use hierarchical spans for flows that take some time, so we can measure the duration. Create sub-spans for critical steps within those flows. Use Span Events for important events or state changes within a span. Example of spans - "QR code claim request/response", page/dialog views, etc. Example of span events - "User clicked 'Claim' button", "http/websocket request failure".
  - **Trace & Span**: Use Trace (or Root Span) for high-level operations (e.g., "Indexing Folder", "Performing Search", "One Backup session") and Sub-Spans for individual steps (e.g., http/websocket request/response, page view).
  - [Mobile] Use Persistent Buffering for logs/spans/metrics to ensure data is not lost on scenario like server down or app crash.
  - [Mobile] Flush on entering background and on app exit.
  - [Mobile] Use batching and compression to optimize network usage.
  - **Correlation** When mobile/pc components interact, ensure to pass correlation IDs in telemetry to link related events across systems.
  - Use standard keys like http.method, device.model.identifier, and os.version.
  - Use `app.device.id` for identifying unique devices in telemetry
  - **Sampling**: For high-volume events, e.g. per file/chunk spans or events, use sampling to reduce server load.
- **Performance Profiling**: Critical functions are often wrapped with a custom `@perffunc` decorator for execution time monitoring.

## 7. Database Operations
- **SQL Execution**: Always use parameterized queries `(?, ?)` for security and stability.
- **Transactions**: Explicit `conn.commit()` calls must follow write operations.
- **Row Access**: The project uses `conn.row_factory = sqlite3.Row` to allow dictionary-like column access by name. Do not rely on tuple indexing unless strictly necessary.
- **Concurrency**: `PRAGMA journal_mode=WAL;` is enabled to resolve multi-writer conflicts. Keep DB connections short-lived or thread-local if writing heavily.

## 8. TESTING
- After adding unit and functional tests, ensure to add then to the [test script](./dt_image_search/scripts/run_tests.sh) so they can be run collectively.
