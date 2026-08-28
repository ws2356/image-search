# Monorepo Agent Guide

## Terminology
- AuSearch: Desktop app featuring semantic image search within local folder; Pairs with AuBackup iOS & Android for mobile album backup - the images backed up can be indexed and searched as well.
- AuBackup: iOS & Android app for file backup.
- InstantShare: Desktop & iOS app for one-shot file/image/text sharing.
- SnapGet: Branding name for InstantShare (InstantShare on apple AppStore is already taken).
- Mobile folder: The term specific to AuSearch desktop app project refering to the mobile album backup feature, as opposed to folders `Local folder`.

This repository contains multiple products/platform combinations.

| Product | Location |
|----------|----------|
| AuSearch Desktop | dt_image_search |
| AuBackup iOS | mobile/ios |
| AuBackup Android | mobile/rn |
| SnapGet Desktop | dt_image_search |
| SnapGet iOS | mobile/instant-share |

## Product Specs

Desktop/iOS/Android implement the same backup & sharing protocol.

Specifications:

- Backup Spec (manually maintained): docs/mobile-folder/
- Sharing Spec (maintained by the superpowers skill): docs/superpowers/

## Shared Engineering Principles

- Ask for clarification if requirements are ambiguous.
- Prefer maintainable solutions over quick fixes.
- Do not duplicate documentation. Instead, maintain a single source of truth and refer to the source as needed.
- Build must pass before task completion.
- Think critically.
- Keep commits small. Leave the LLM name in the commit message with format `[LLM: <LLM_NAME>]` where `<LLM_NAME>` can be, e.g. gpt-5.4, gpt-5.3-codex, opus-4.7, deepseek-v4-pro, glm-5.1, opencode/mimo-v2.5-pro ..., which will be used for audit and assessment of the LLM's performance.
- The `SOLID` principles.  Single Responsibility (Every module, class, or function should be responsible for a single part of the functionality); Open/Closed (You should be able to add new features or behaviors without changing the existing source code); Liskov Substitution (Don't "empty out" inherited methods. If a subclass cannot actually perform the action of its parent, the inheritance hierarchy is wrong); Interface Segregation (It is better to have many small, specific interfaces than one large, general-purpose one); Dependency Inversion (Use Dependency Injection).
- DRY (Don't Repeat Yourself). Abstract common logic into reusable functions or modules. Avoid copy-pasting code blocks.
- KISS (Keep It Simple, Stupid). Avoid over-engineering. Choose the simplest solution that fully satisfies the requirements.
- YAGNI (You Ain't Gonna Need It). Do not add functionality until it is necessary. Avoid "future-proofing" that complicates the current design.

- **Clean &amp; Maintainable Code**: Clean &amp; Maintanable code is as important functionality. Always ask yourself if there are cleaner &amp; simpler plan/implementation that satisfies the requirements, even when that means the requirement to refactor existing code in which case you need to pause and ask the user whether do a refactor first before implementing the new changes.
- **One way to do things**: For any given problem, there should ideally be one clear and consistent way to solve it within the codebase. This reduces cognitive load and makes it easier for developers to understand and contribute.
- **Separation of Concerns**: UI code should not contain business logic. Business logic should be in separate controller or worker classes. Each file should have a clear and often singular responsibility.
- **Design Patterns**: Use approriate design patterns, e.g. DI, MVC, MVVM, TCA, State Machine, etc. where they fit naturally.
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

## Layered Testing Strategy (The Testing Pyramid)

### Unit Testing (Foundation: High-Frequency, Millisecond-Speed, Lowest Cost)

- Targeting pure decision functions, state machine transitions, and data mapping/transformation utilities and the likes.
- **Assert behavior, not implementation details**: Verify *"Given input X, expect output Y"*. Do not test internal method calls to keep tests resilient against code refactoring.
- **One test case per decision branch**: Keep assertions focused to pinpoint the exact root cause upon failure.
- **Testing complex state machines**: Avoid mocking internal state logic. Instead, construct a test harness by injecting outermost edge dependencies (e.g., controllable clocks, task executors) to enforce contracts around *execution order, race conditions, and retry flows*.
- Do not chase 100% line coverage; target **decision branch coverage** instead.
- Do not test third-party libraries.


### Integration Testing (High-ROI)

- Targeting interactions between multiple real modules (e.g., `Auth` module + `Permission` module).
- **Use real implementations** for internal modules—avoid hollow mocks.
- Confine mocking strictly to the **outermost boundaries** between the system and the external world (Network I/O, System Clock, Storage).