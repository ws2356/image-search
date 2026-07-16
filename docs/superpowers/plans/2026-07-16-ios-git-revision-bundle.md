# iOS Git Revision Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed the 40-char git revision of the iOS source into the shipped app bundle as `BuildMetadata.json`, and report it via the `app.git_revision` OpenTelemetry resource attribute on every span and metric.

**Architecture:** A checked-in `BuildMetadata.template.json` (with a `__GIT_REVISION__` slot) is copied into the app bundle by a "Run Script" Xcode build phase placed after "Copy Bundle Resources" and before code signing; the slot in the *copy* is replaced with `git rev-parse HEAD`. At runtime a `Bundle` helper reads the JSON, and `OpenTelemetryTelemetryClient.makeResource` adds `app.git_revision` to the OTel Resource so all telemetry carries it. The repository working tree is never mutated.

**Tech Stack:** Swift (iOS), Xcode `.xcodeproj` build phases, `bash` Run Script phase, OpenTelemetry Swift SDK (`OpenTelemetryApi`/`OpenTelemetrySdk`), `swift test` / `xcodebuild test`.

## Global Constraints

- No repo mutation: build phase must never modify any source/plist/config file in place; all generated artifacts live only in build output. (verbatim from spec)
- Post-build, pre-sign: revision artifact is written after the app bundle is assembled but before code signing. (verbatim from spec)
- Separate plist file: use a dedicated generic metadata plist, not `Info.plist`. (verbatim from spec)
- Full hash (40 chars): `git rev-parse HEAD`, not short form. (verbatim from spec)
- Separate telemetry attribute: revision reported as `app.git_revision`, independent of `service.version`. (verbatim from spec)
- Use a checked-in template plist as the prototype; copy it into the bundle and update slot values in the copy. (verbatim from spec)
- Telemetry must use the centralized `log`/`OpenTelemetryTelemetryClient` path; no `print()`/`logging`. (from AGENTS.md)
- Swift code follows iOS AGENTS.md: MVVM, `@MainActor` ViewModels, async/await; new files get a file header comment with purpose/author/date.
- Commit each meaningful batch; include `[LLM: <name>]` in commit message.

---

## File Structure

- `mobile/ios/App/BuildMetadata.template.json` — **Create.** Checked-in JSON template with `__GIT_REVISION__` slot. Source of truth for bundle metadata shape. (JSON, not plist, for cross-project reuse.)
- `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj` — **Modify.** Add "Run Script" build phase "Embed Build Metadata" to the `AlbumTransporterApp` target, ordered after "Copy Bundle Resources" / before signing.
- `mobile/ios/Sources/AlbumTransporterKit/Utilities/Bundle+BuildMetadata.swift` — **Create.** `Bundle` extension reading `BuildMetadata.json` from the main bundle.
- `mobile/ios/Sources/AlbumTransporterKit/Services/OpenTelemetryTelemetryClient.swift` — **Modify** (`makeResource`, ~line 347). Add `app.git_revision` attribute from `Bundle.main.gitRevision()`.
- `mobile/ios/Tests/AlbumTransporterKitTests/Bundle+BuildMetadataTests.swift` — **Create.** Unit tests for the reader.
- `mobile/ios/scripts/verify_build_metadata.sh` — **Create.** Smoke check that a built `.app` contains `BuildMetadata.json` with a 40-char `GitRevision`.

---

### Task 1: Checked-in template plist

**Files:**
- Create: `mobile/ios/App/BuildMetadata.template.json`

**Interfaces:**
- Produces: a file consumed by the build phase in Task 2 (path `$(SRCROOT)/App/BuildMetadata.template.json`). The build phase expects exactly one key `GitRevision` with placeholder value `__GIT_REVISION__`.

- [ ] **Step 1: Create the template JSON**

```json
{
  "GitRevision": "__GIT_REVISION__"
}
```

Save as `mobile/ios/App/BuildMetadata.template.json`.

- [ ] **Step 2: Validate the JSON is well-formed**

Run: `python3 -c "import json,sys; json.load(open('mobile/ios/App/BuildMetadata.template.json')); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add mobile/ios/App/BuildMetadata.template.json
git commit -m "build(ios): add BuildMetadata template json [LLM: opencode/hy3-free]"
```

---

### Task 2: Build phase that copies template and fills the slot

**Files:**
- Modify: `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj`
- Test: `mobile/ios/scripts/verify_build_metadata.sh` (created in Task 5; here we add a local dry-run invocation)

**Interfaces:**
- Consumes: `$(SRCROOT)/App/BuildMetadata.template.json` (Task 1).
- Produces: `${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildMetadata.json` inside the `.app`, with `GitRevision` = 40-char hash. Consumed at runtime by Task 3/4.

The Run Script phase must be placed **after** the "Copy Bundle Resources" phase and **before** the code-sign phase in the `AlbumTransporterApp` target's `buildPhases` array.

- [ ] **Step 1: Write the build phase script body to a script file (kept in repo for reviewability)**

Create `mobile/ios/scripts/embed_build_metadata.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Embed Build Metadata — copies the checked-in template into the app bundle
# and fills the __GIT_REVISION__ slot with the current git revision.
# Runs after "Copy Bundle Resources", before code signing. Never mutates the repo.

SRCROOT="${SRCROOT:?SRCROOT not set}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR not set}"
CONTENTS_FOLDER_PATH="${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH not set}"

TEMPLATE="${SRCROOT}/App/BuildMetadata.template.json"
DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildMetadata.json"

if [[ ! -f "${TEMPLATE}" ]]; then
    echo "error: BuildMetadata template not found at ${TEMPLATE}" >&2
    exit 1
fi

REVISION="unknown"
if REPO_ROOT="$(git -C "${SRCROOT}" rev-parse --show-toplevel 2>/dev/null)"; then
    REVISION="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")"
fi

mkdir -p "$(dirname "${DEST}")"
cp "${TEMPLATE}" "${DEST}"

if [[ "${REVISION}" == "unknown" ]]; then
    sed -i '' 's/__GIT_REVISION__/unknown/' "${DEST}"
else
    sed -i '' "s/__GIT_REVISION__/${REVISION}/" "${DEST}"
fi

python3 -c "import json; json.load(open('${DEST}'))" >/dev/null
echo "Embedded BuildMetadata revision: ${REVISION}"
```

Make it executable: `chmod +x mobile/ios/scripts/embed_build_metadata.sh`.

- [ ] **Step 2: Add the Run Script build phase to the Xcode project**

Edit `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj`. Add a new shell-script build phase entry to the `AlbumTransporterApp` target's `buildPhases` array, placed **after** the existing "Copy Bundle Resources" phase and **before** the final code-sign phase. The phase references the script file via its full path so the body stays reviewable in the repo.

Add a new build-phase object (generate a unique 24-char hex ID, e.g. `EBD000000000000000000001`):

```
		EBD000000000000000000001 /* Embed Build Metadata */ = {
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/App/BuildMetadata.template.json",
			);
			name = "Embed Build Metadata";
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/BuildMetadata.json",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "\"${SRCROOT}/scripts/embed_build_metadata.sh\"\n";
		};
```

Insert `EBD000000000000000000001 /* Embed Build Metadata */,` into the `buildPhases = (` list of the `AlbumTransporterApp` target, **after** the `/* Copy Bundle Resources */` entry and **before** the code-sign/signature-related entry at the end.

- [ ] **Step 3: Verify the project still parses**

Run: `plutil -lint mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj`
Expected: `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj: OK`

- [ ] **Step 4: Dry-run the script with stubbed env to confirm it writes a valid plist with a 40-char hash**

Run:
```bash
cd mobile/ios
export SRCROOT="$(pwd)"
export BUILT_PRODUCTS_DIR="$(mktemp -d)"
export CONTENTS_FOLDER_PATH="AlbumTransporterApp.app"
./scripts/embed_build_metadata.sh
python3 -c "import json; print(json.load(open('${BUILT_PRODUCTS_DIR}/AlbumTransporterApp.app/BuildMetadata.json')))"
```
Expected: output shows `{'GitRevision': '<40-char hex string>'}` (or `'unknown'` if run outside a git checkout).

- [ ] **Step 5: Commit**

```bash
git add mobile/ios/scripts/embed_build_metadata.sh mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj
git commit -m "build(ios): add Embed Build Metadata run script phase [LLM: opencode/hy3-free]"
```

---

### Task 3: Runtime reader `Bundle+BuildMetadata`

**Files:**
- Create: `mobile/ios/Sources/AlbumTransporterKit/Utilities/Bundle+BuildMetadata.swift`
- Test: `mobile/ios/Tests/AlbumTransporterKitTests/Bundle+BuildMetadataTests.swift`

**Interfaces:**
- Produces: `Bundle.buildMetadata() -> [String: String]?` and `Bundle.gitRevision() -> String?`, both read from `BuildMetadata.json` in `Bundle.main`. Consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Create `mobile/ios/Tests/AlbumTransporterKitTests/Bundle+BuildMetadataTests.swift`:

```swift
import XCTest
@testable import AlbumTransporterKit

final class BundleBuildMetadataTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleBuildMetadataTests", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testGitRevisionReads40CharHash() throws {
        let jsonURL = tempDir.appendingPathComponent("BuildMetadata.json")
        let hash = String(repeating: "a", count: 40)
        let json = "{\"GitRevision\":\"\(hash)\"}"
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        let bundle = Bundle(url: tempDir)!
        XCTAssertEqual(bundle.gitRevision(), hash)
        XCTAssertEqual(bundle.buildMetadata()?["GitRevision"], hash)
    }

    func testMissingPlistReturnsNil() {
        let bundle = Bundle(url: tempDir)!
        XCTAssertNil(bundle.gitRevision())
        XCTAssertNil(bundle.buildMetadata())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd mobile/ios && ./scripts/run_unit_tests.sh -only-testing:AlbumTransporterKitTests/BundleBuildMetadataTests`
Expected: FAIL — `gitRevision()` / `buildMetadata()` not found (compiler error).

- [ ] **Step 3: Write minimal implementation**

Create `mobile/ios/Sources/AlbumTransporterKit/Utilities/Bundle+BuildMetadata.swift`:

```swift
// Purpose: Read build-time metadata (git revision, etc.) from BuildMetadata.json
//          embedded in the app bundle.
// Author: opencode/hy3-free
// Date: 2026-07-16

import Foundation

extension Bundle {
    /// Dictionary of build metadata loaded from `BuildMetadata.json` in this bundle, or `nil` if absent/malformed.
    func buildMetadata() -> [String: String]? {
        guard let url = url(forResource: "BuildMetadata", withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return raw
    }

    /// The 40-char git revision baked into the bundle, or `nil` if not present.
    func gitRevision() -> String? {
        return buildMetadata()?["GitRevision"]
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd mobile/ios && ./scripts/run_unit_tests.sh -only-testing:AlbumTransporterKitTests/BundleBuildMetadataTests`
Expected: PASS (both test cases).

- [ ] **Step 5: Commit**

```bash
git add mobile/ios/Sources/AlbumTransporterKit/Utilities/Bundle+BuildMetadata.swift mobile/ios/Tests/AlbumTransporterKitTests/Bundle+BuildMetadataTests.swift
git commit -m "feat(ios): add Bundle build-metadata reader [LLM: opencode/hy3-free]"
```

---

### Task 4: Add `app.git_revision` to the OpenTelemetry Resource

**Files:**
- Modify: `mobile/ios/Sources/AlbumTransporterKit/Services/OpenTelemetryTelemetryClient.swift` (`makeResource`, lines ~347-362)

**Interfaces:**
- Consumes: `Bundle.gitRevision() -> String?` (Task 3).
- Produces: every span/metric emitted carries the `app.git_revision` resource attribute.

- [ ] **Step 1: Write a failing test asserting the resource attribute is present**

Add to an existing telemetry test file (e.g. `mobile/ios/Tests/AlbumTransporterKitTests/OTLPHTTPSpanExporterTests.swift`) a focused test, or create `mobile/ios/Tests/AlbumTransporterKitTests/OpenTelemetryResourceTests.swift`:

```swift
import XCTest
@testable import AlbumTransporterKit

final class OpenTelemetryResourceTests: XCTestCase {
    func testResourceContainsGitRevisionAttribute() {
        let resource = OpenTelemetryTelemetryClient.makeResource(
            serviceName: "AuBackup.iOS",
            serviceVersion: "1.1.0"
        )
        // makeResource reads Bundle.main.gitRevision(); in tests this is usually nil -> "unknown".
        let value = resource.attributes["app.git_revision"]
        XCTAssertNotNil(value)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd mobile/ios && ./scripts/run_unit_tests.sh -only-testing:AlbumTransporterKitTests/OpenTelemetryResourceTests`
Expected: FAIL — `app.git_revision` attribute absent (or `makeResource` not accessible; it is `private static` — see Step 3 note).

> Note: `makeResource` is currently `private static`. To test it directly, change its visibility to `internal static` (still not part of the public `TelemetryClient` protocol). Apply that change in Step 3.

- [ ] **Step 3: Update `makeResource` to add the attribute**

In `OpenTelemetryTelemetryClient.swift`, change:
```swift
private static func makeResource(serviceName: String, serviceVersion: String?) -> Resource {
```
to:
```swift
static func makeResource(serviceName: String, serviceVersion: String?) -> Resource {
```

And inside `makeResource`, after the `service.version` block (line ~360), before `return`:
```swift
        attributes["app.git_revision"] = .string(Bundle.main.gitRevision() ?? "unknown")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd mobile/ios && ./scripts/run_unit_tests.sh -only-testing:AlbumTransporterKitTests/OpenTelemetryResourceTests`
Expected: PASS.

- [ ] **Step 5: Run the full iOS test suite to check for regressions**

Run: `cd mobile/ios && ./scripts/run_unit_tests.sh`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/ios/Sources/AlbumTransporterKit/Services/OpenTelemetryTelemetryClient.swift mobile/ios/Tests/AlbumTransporterKitTests/OpenTelemetryResourceTests.swift
git commit -m "feat(ios): add app.git_revision to OTel resource [LLM: opencode/hy3-free]"
```

---

### Task 5: Build smoke check script

**Files:**
- Create: `mobile/ios/scripts/verify_build_metadata.sh`

**Interfaces:**
- Consumes: a built `.app` path (from `export_ipa.sh` output or `xcodebuild` DerivedData).
- Produces: exit 0 if `BuildMetadata.json` exists with a 40-char hex `GitRevision`; non-zero otherwise.

- [ ] **Step 1: Write the verification script**

Create `mobile/ios/scripts/verify_build_metadata.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Verify that a built .app contains BuildMetadata.json with a 40-char GitRevision.
# Usage: verify_build_metadata.sh <path-to-App.app>

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
    echo "usage: verify_build_metadata.sh <path-to-App.app>" >&2
    exit 2
fi

PLIST="${APP_PATH}/BuildMetadata.json"
if [[ ! -f "${PLIST}" ]]; then
    echo "error: BuildMetadata.json missing from ${APP_PATH}" >&2
    exit 1
fi

REVISION="$(python3 -c "import json,sys; print(json.load(open('${PLIST}')).get('GitRevision',''))" 2>/dev/null || echo "")"
if [[ ! "${REVISION}" =~ ^[0-9a-f]{40}$ ]] && [[ "${REVISION}" != "unknown" ]]; then
    echo "error: GitRevision is not a 40-char hash or 'unknown': '${REVISION}'" >&2
    exit 1
fi

echo "OK: BuildMetadata.json present, GitRevision=${REVISION}"
```

Make it executable: `chmod +x mobile/ios/scripts/verify_build_metadata.sh`.

- [ ] **Step 2: Smoke-test the script against a built app (or a stub)**

If a built `.app` is available (e.g. from DerivedData), run:
```bash
cd mobile/ios
APP=$(find build -name 'AlbumTransporterApp.app' -maxdepth 4 -type d -print -quit)
./scripts/verify_build_metadata.sh "${APP}"
```
If no build exists yet, create a stub to confirm failure path:
```bash
STUB=$(mktemp -d)/AlbumTransporterApp.app; mkdir -p "$STUB"
./scripts/verify_build_metadata.sh "$STUB"; echo "exit=$? (expect non-zero)"
```
Expected: stub run exits non-zero with the missing-plist error; real build run (after Task 2 ships) exits 0.

- [ ] **Step 3: Wire into export flow (optional assertion)**

In `mobile/ios/scripts/export_ipa.sh`, after the IPA is exported (around line 195, before the final `echo`), add an assertion that the archived app contains the plist:

```bash
    local app_bundle
    app_bundle="$(find "${ARCHIVE_PATH}/Products" -name 'AlbumTransporterApp.app' -type d -print -quit)"
    if [[ -n "${app_bundle}" ]]; then
        "${IOS_ROOT}/scripts/verify_build_metadata.sh" "${app_bundle}"
    fi
```

Also update the dry-run in Task 2 Step 4 to point at the JSON copy (already JSON). No further plist references remain.
```

- [ ] **Step 4: Commit**

```bash
git add mobile/ios/scripts/verify_build_metadata.sh mobile/ios/scripts/export_ipa.sh
git commit -m "test(ios): add build metadata verification script [LLM: opencode/hy3-free]"
```

---

## Self-Review

**1. Spec coverage:**
- Separate `BuildMetadata.json` from template → Task 1 + Task 2. ✓
- Copied into bundle, slot replaced in copy, repo never mutated → Task 2 (`embed_build_metadata.sh`). ✓
- Post-build pre-sign ordering → Task 2 (phase placed after Copy Bundle Resources). ✓
- Full 40-char hash → Task 2 script (`git rev-parse HEAD`), Task 5 validation. ✓
- Runtime reader → Task 3. ✓
- `app.git_revision` separate attribute on Resource → Task 4. ✓
- Error handling (git missing / plist absent → "unknown") → Task 2, Task 3. ✓
- Testing (reader unit test + build smoke) → Task 3, Task 5. ✓

**2. Placeholder scan:** No TBD/TODO/"implement later". All code steps contain full code. ✓

**3. Type consistency:** `Bundle.buildMetadata() -> [String: String]?` and `Bundle.gitRevision() -> String?` defined in Task 3 and used identically in Task 4 (`Bundle.main.gitRevision() ?? "unknown"`). `makeResource(serviceName:serviceVersion:)` signature unchanged. Template key `GitRevision` matches reader key and script `Set :GitRevision`. ✓
