# **AuBackup (iOS)**

This iOS project implements the AuBackup app, which offers mobile album backup to PC and instant sharing features.
For specs on backup feature, see [AuBackup Specs](../../dt_image_search//specs/).
For specs on sharing feature, see [AuShare Specs](../../openspec/).

## **1\. Architecture and State Management**

Only pairing page is depicted in this diagram for simplicity. The root view is `RootView`, which contains a `RootViewModel` that manages the state machine. The state machine in `RootViewModel` controls the navigation and state transitions between different pages. Each page uses its own ViewModel to manage its local state and business logic and telemetry. The ViewModels communicate with the RootViewModel to trigger state transitions.
```mermaid
flowchart TD
    %% 样式定义
    classDef root fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef view fill:#fff3e0,stroke:#f57c00,stroke-width:1px;
    classDef vm fill:#f1f8e9,stroke:#689f38,stroke-width:1px;
    classDef telemetry fill:#fce4ec,stroke:#c2185b,stroke-width:1px,stroke-dasharray: 5 5;

    %% 根层级
    subgraph Root_Layer [根管理层]
        RVM[RootViewModel\n- state: Enum\n- 状态机控制]:::root
        RV[RootView\n- @StateObject rootVM]:::view
    end

    %% 子页面层级
    subgraph Sub_Layer [动态子页面层]
        PV[PairingView\n- @StateObject pairingVM]:::view
        PVM[PairingViewModel]:::vm
    end

    %% 埋点分流展示
    subgraph Telemetry_Layer [Telemetry Service]
        T_Click[UI事件]:::telemetry
        T_Funnel[业务事件]:::telemetry
    end

    %% 关系连线
    RV -->|1. 绑定 $state| PV
    PV -->|2. UI Events | PVM
    
    PVM -->|3. Local State | PV
    PVM -->|4. onPairingCompleted delegate| RVM
    RVM -->|5. 修改 state 改变状态| RV

    %% 埋点映射
    PVM -.->|PageView/PageAction| T_Click
    PVM -.->|业务事件| T_Funnel
```
Proper state flow is critical in SwiftUI to prevent unexpected UI behavior and performance bottlenecks.

| Guideline | Agent Guidance   |
| :---- | :---- |
| **MVVM or Composable Architecture** | Prefer MVVM (Model-View-ViewModel) design pattern. Keep Views "dumb" and move business logic into the ViewModel or a separate Domain layer. |
| **Single Source of Truth** | Use @State for local private view state, @Binding for passing state down, and @StateObject / @ObservedObject for external data sources. |
| **Observable Macro** | For iOS 17+, prioritize the @Observable macro over ObservableObject to benefit from more granular view updates. |

## **2\. SwiftUI View Best Practices**

* **Atomic Views:** Break down large views into smaller, reusable components. If a body exceeds 30-40 lines, extract subviews.  
* **Avoid View Composition in body:** Move complex conditional logic or sub-view generation into separate computed properties or helper functions.  
* **Preview Driven Development:** Always provide \#Preview blocks with mock data to ensure components are testable in isolation.  
* **Layout Safety:** Always respect the Safe Area and use Spacer(), HStack, VStack, and ZStack intentionally for adaptive layouts.

### **Example: Subview Extraction**

`// Preferred: Clear, extracted subviews`  
`struct ProfileView: View {`  
    `var body: some View {`  
        `VStack {`  
            `ProfileHeader()`  
            `ProfileStats()`  
            `LogoutButton()`  
        `}`  
    `}`  
`}`

## **3\. Concurrency and Data Fetching**

Utilize Swift's modern concurrency model to keep the UI responsive.

* **Async/Await:** Use async/await for network calls and asynchronous tasks instead of completion handlers.  
* **MainActor:** Ensure UI updates are always performed on the @MainActor. ViewModels should typically be marked with @MainActor.  
* **Task Modifier:** Use the .task view modifier for triggering data fetches when a view appears; it handles automatic cancellation when the view disappears.

## **4\. Performance Optimization**

* **Lazy Containers:** Use LazyVStack, LazyHStack, and LazyVGrid for large lists to ensure views are only rendered when they enter the screen.  
* **Identifiable Protocols:** Ensure models used in ForEach or List conform to Identifiable to help SwiftUI optimize identity tracking and animations.  
* **Asset Optimization:** Use SF Symbols where possible and ensure custom images are provided in @2x and @3x scales or as vectors (PDF/SVG).

## **5\. Testing in iOS**

- **snapshot tests**: Run `cd mobile/ios && scripts/run_snapshot_tests.sh --mode test` to assert the committed launch/home/transfer/completion snapshots on the configured simulator devices. Run `cd mobile/ios && scripts/run_snapshot_tests.sh --mode record` to update the baseline snapthots. Snapshot filenames include page, device model, and language, e.g. `launch-splash_iPhone-17-Pro-Max_en-US.png`.
- **unit tests**: Run `cd mobile/ios && xcodebuild test -project AlbumTransporterApp.xcodeproj -scheme AlbumTransporterApp -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -skip-testing:AlbumTransporterAppSnapshotTests/AlbumTransporterAppSnapshotTests`. Use `-only-testing:AlbumTransporterAppSnapshotTests/<TestCaseName>` or `-only-testing:AlbumTransporterAppSnapshotTests/<TestCaseName>/<testMethod>` for focused test runs. The USB functional challenge test expects a Python environment where `python3.10` can import `websockets.sync.client`; you can use the same venv used by the PC side.

## **6\. Development Environment Setup**
- **Use rbenv**: brew install rbenv ruby-build
- **Install Ruby**: rbenv install 3.2.2 && rbenv local 3.2.2
- **Use Bundler**: gem install bundler && bundle install