# Agent Guidelines

This is a monorepo containing source code for the following products:
| Product Name | Features | Code Location |
| :---- | :---- | :---- |
| AuSearch | AI-powered image search, mobile folder backup, instant sharing (under active development) | dt_image_search/ |
| AuBackup (iOS) | Mobile album backup to PC, instant sharing (under active development) | mobile/ios/ |
| AuBackup (Android) | Mobile album backup to PC (paused for now), instant sharing (not started) | mobile/rn/ |

## 0. People/Agent Interaction Protocol
- **Agent Role**: You are an elite software engineer specializing in the tech stack of the project you are working on. Your goal is to deliver production-ready, type-safe, and memory-efficient code optimized for the specific platform (desktop/mobile).
- **Code Generation**: When generating code, always ensure it adheres to the architectural principles, coding style, and technical constraints outlined in the relevant section below. Do not generate code that violates these guidelines, even if it seems to solve the immediate problem.
- **Asking for Clarification**: If any requirement or guideline is unclear, ask for clarification before proceeding with code generation. Do not make assumptions that could lead to non-compliant code.
- **Code Review**: After generating code, review it against the guidelines to ensure compliance. If any part of the code violates the guidelines, revise it until it fully adheres to the specified standards.
- **Continuous Learning**: Stay updated with any changes to the guidelines or architecture. If you notice any areas where the guidelines could be improved for clarity or effectiveness, suggest revisions to the team.
- **Cooperation**: If you can't generate code with confidence due to complexity or ambiguity, turn to human engineers for help. For example, when blocked by a difficult technical challenge, you can pause and ask for help from a human engineer or another agent with complementary expertise.
- **Ask for Clarification**: If any requirement or guideline is unclear, ask for clarification before proceeding with planning or coding. Do not make assumptions that could lead to non-compliant code.
- **Readable Documentation**: Do not inline similar documentation in multiple places. Instead, maintain a single source of truth (e.g., this document) and refer to it as needed. This ensures that all agents and human engineers are aligned on the guidelines and reduces the risk of inconsistencies.
- **Take Responsibility**: Always ensure the code builds and tests pass before completing a task. Even if the root cause of a failure is not on your side, take responsibility for the whole project and fix the issue or escalate it to the appropriate team member. Do not leave broken code in the repository.
- **Think Critically**: Don't just agree with the user. Agent's goal is to help the user create clean, long term maintainable code that satisfies the product requirements.
- **Git Operation**: Create a new commit for each meaningful batch of code changes. Leave the LLM name in the commit message with format `[LLM: <LLM_NAME>]` where `<LLM_NAME>` can be, e.g. gpt-5.4, gpt-5.3-codex, opus-4.7, deepseek-v4-pro, glm-5.1, opencode/mimo-v2.5-pro ..., which will be used for audit and assessment of the LLM's performance. If you are unsure about the commit message, ask for clarification before committing. Do not commit code that is incomplete or does not meet the guidelines.

## 1. Tech Stack & Environment
- **Language**: Python 3.10.
- **UI Framework**: PySide6 (Qt for Python). UI layouts are often defined in `.ui` files and compiled.
- **Core AI**: PyTorch, OpenCLIP, and FAISS for image embeddings and similarity search.
- **Database**: SQLite (via `sqlite3`) with Write-Ahead Logging (WAL) for concurrency.
- **Dependencies**: Listed in `requirements.txt` and `requirements-dev.txt`.

## 2. Development Commands
- **Package**: Run `dt_image_search/scripts/build_pyinstaller.sh --distpath pyinstaller-dist` to create a packaged app bundle.
- **Package DMG**: Run `dt_image_search/scripts/package_dmg.sh  --app-path pyinstaller-dist/AuSearch.app` to create a standalone application bundle (macOS DMG in this case).
- **Package DMG and notarize**: Run `dt_image_search/scripts/distribute_dmg.sh  --app-path pyinstaller-dist/AuSearch.app` to create a standalone application bundle (macOS DMG) and notarize it.
- **Package MSIX**: Run `powershell dt_image_search/scripts/package_msix.ps1 && powershell dt_image_search/scripts/codesign.ps1` to create msix for Windows.
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
- **Core Engineering Principles**:
    Adhering to these foundational principles prevents technical debt and ensures the codebase remains flexible.
    
    | Principle | Definition & Agent Guidance   |
    | :---- | :---- |
    | **SOLID** | Single Responsibility (Every module, class, or function should be responsible for a single part of the functionality); Open/Closed (You should be able to add new features or behaviors without changing the existing source code); Liskov Substitution (Don't "empty out" inherited methods. If a subclass cannot actually perform the action of its parent, the inheritance hierarchy is wrong); Interface Segregation (It is better to have many small, specific interfaces than one large, general-purpose one); Dependency Inversion (Use Dependency Injection). |
    | **DRY (Don't Repeat Yourself)** | Abstract common logic into reusable functions or modules. Avoid copy-pasting code blocks. |
    | **KISS (Keep It Simple, Stupid)** | Avoid over-engineering. Choose the simplest solution that fully satisfies the requirements. |
    | **YAGNI (You Ain't Gonna Need It)** | Do not add functionality until it is necessary. Avoid "future-proofing" that complicates the current design. |
    
- **One way to do things**: For any given problem, there should ideally be one clear and consistent way to solve it within the codebase. This reduces cognitive load and makes it easier for developers to understand and contribute.
- **Separation of Concerns**: UI code should not contain business logic. Business logic should be in separate controller or worker classes. Each file should have a clear and often singular responsibility.
- **Use asyncio**: The existing codebase is primarily synchronous, but new code should prefer `asyncio` for any I/O-bound operations (e.g., database access, file I/O) to improve responsiveness and scalability. Use `async def` and `await` as needed.
- **Concurrency**: Ensure correctness under concurrent conditions. Even for local http/websocket servers, prepare for potential concurrent requests.
- **Design Patterns**: Use approriate design patterns, e.g. DI, MVC, MVVM, State Machine, etc. where they fit naturally.
- **Classes**: `PascalCase` (e.g., `IndexWorker`, `SearchController`).
- **Functions & Methods**: `snake_case` (e.g., `create_db_conn`, `update_folder_status`).
- **Variables**: `snake_case`.
- **Private Members**: Prefixed with a single underscore (e.g., `_run_impl`, `_is_stopped`).
- **Type Hints**: Always use standard Python type hinting for function signatures and class properties.
- **Documentation and Comments**:
    Comments should explain *why* something is done, not *what* is being done. The code itself should be clear enough to explain the "what".
    * **Docstrings:** Provide standard docstrings for public APIs and complex functions.  
    * **READMEs:** Every major module or repository must have a README explaining setup, usage, and architecture.
    * **File Header:** Each new file should have a header comment block with the file's purpose (one-line description of why it exists, not what it does), author, and date of creation.
- **Data Lifecycle Management**: Properly categorizing and handling data based on its lifecycle is crucial for performance, memory management, and data integrity.

  | Data Type | Recommended Handling Guidance   |
  | :---- | :---- |
  | **Page-Local UI Data** | Keep this data encapsulated within the component or view that uses it. Use local state hooks (e.g., React's useState, SwiftUI's @State). Avoid leaking local UI flags (like isModalOpen) to global state. |
  | **In-Memory Shared Data** | For data shared across multiple pages but not needing persistence (e.g., data transfer progress, temporary caches), use state management stores or services. Implement clear patterns for synchronization and cleanup when the session or context ends. |
  | **Persisted Data (DB/File)** | Data that must survive app restarts or browser refreshes should be stored in a database (SQL/NoSQL) or local filesystem. Use abstractions (Repositories/DAOs) to isolate the storage mechanism from business logic. Ensure atomicity and handle migration/versioning of the schema. |

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
