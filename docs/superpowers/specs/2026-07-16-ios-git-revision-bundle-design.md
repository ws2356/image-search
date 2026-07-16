# Design: Git Revision in iOS App Bundle

**Date:** 2026-07-16
**Status:** Approved
**Product:** AuBackup (iOS) — `mobile/ios`

## Goal

Embed the git revision (full 40-char commit hash) of the iOS source into the
shipped app bundle so that production telemetry can carry it as a dedicated
attribute. This makes it possible to trace any telemetry event back to the exact
code revision that produced it.

## Constraints (from requirements)

1. **No repo mutation.** The build must never modify any source, plist, or config
   file in place. All generated artifacts live only in the build output / derived
   data.
2. **Post-build, pre-sign.** The revision artifact is written *after* the app
   bundle is assembled but *before* code signing, so it is included in the code
   signature and lands in the `.ipa` automatically.
3. **Separate plist file.** Reuse of the existing `Info.plist` is avoided; a
   dedicated, generic metadata plist is created instead so more fields can be
   added later.
4. **Full hash (40 chars).** `git rev-parse HEAD`, not the short form.
5. **Separate telemetry attribute.** The revision is reported as its own span /
   metric attribute (`app.git_revision`), independent of `service.version`.

## Architecture

```
 git (repo root)
      │  rev-parse HEAD
      ▼
 [Run Script build phase: "Embed Build Metadata"]
      │  writes BuildMetadata.plist into .app bundle (pre-sign)
      ▼
 ${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildMetadata.plist
      │  signed + packaged into .ipa
      ▼
 Runtime: Bundle.main → BuildMetadata.plist → gitRevision
      │
      ▼
 OpenTelemetry Resource attribute: app.git_revision
      │
      ▼
 Every span & metric exported to OTLP carries the revision
```

## Components

### 1. Build phase — "Embed Build Metadata"

A new **Run Script** build phase added to the `AlbumTransporterApp` target in
`AlbumTransporterApp.xcodeproj`, placed **after** "Copy Bundle Resources" and
**before** the implicit code-sign step.

A **template plist is checked into the repository** and used as the prototype:

- Path: `mobile/ios/App/BuildMetadata.template.plist` (or
  `mobile/ios/Resources/BuildMetadata.template.plist`)
- Checked in, version-controlled, and **never mutated in place** at build time.

Template contents (v1):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GitRevision</key>
    <string>__GIT_REVISION__</string>
</dict>
</plist>
```

Build phase behavior:
- Resolve repo root: `git -C "${SRCROOT}" rev-parse --show-toplevel`
- Compute full hash: `git -C "${REPO_ROOT}" rev-parse HEAD`
- **Copy** the checked-in template into the app bundle:
  `${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildMetadata.plist`
- Update the slot value in the copied file: replace `__GIT_REVISION__` with the
  resolved hash (e.g. via `sed -i ''` on the copied file, or `PlistBuddy` on the
  copy). The template in the repo is left untouched → repo stays clean.

Rationale for separate template file: `BuildMetadata.plist` is generic and
structured as a dictionary, so future fields (build date, CI run id, pipeline
id, etc.) can be added by extending the template and the slot-replacement step,
without generating XML from scratch.

### 2. Runtime reader

A small helper in `AlbumTransporterKit`, e.g.
`Sources/AlbumTransporterKit/Utilities/Bundle+BuildMetadata.swift`:

- `Bundle.buildMetadata() -> [String: String]?` loads `BuildMetadata.plist` from
  `Bundle.main` and returns its dictionary.
- Convenience accessor `Bundle.gitRevision() -> String?` returns
  `buildMetadata()?["GitRevision"]`.
- Returns `nil` when the plist is absent (simulator / test runs where the build
  phase did not populate it), so callers apply a fallback.

### 3. Telemetry integration

In `OpenTelemetryTelemetryClient.makeResource`
(`Sources/AlbumTransporterKit/Services/OpenTelemetryTelemetryClient.swift:347`):
add the revision to the OTel `Resource` attributes:

```swift
attributes["app.git_revision"] = .string(Bundle.main.gitRevision() ?? "unknown")
```

Placing it on the `Resource` guarantees every span and metric carries
`app.git_revision` automatically — no per-event changes required elsewhere.

## Error Handling

| Case | Behavior |
| :---- | :---- |
| Git missing / not a repo at build time | Phase leaves `__GIT_REVISION__` unresolved (or writes `"unknown"`); build succeeds |
| Template plist missing from repo | Phase fails the build (template must be present) |
| Plist absent at runtime (simulator/tests) | Reader returns `nil`; telemetry uses `"unknown"` |
| Malformed plist at runtime | Reader returns `nil`; telemetry uses `"unknown"` |

## Testing

1. **Reader unit test** — exercise `Bundle.buildMetadata()` / `gitRevision()`
   with (a) an injected temp `BuildMetadata.plist` containing a known 40-char
   hash (assert parsed correctly), and (b) no file present (assert `nil`).
2. **Build smoke check** — verify that a built `.app` (via `export_ipa.sh` or a
   `xcodebuild archive`) contains `BuildMetadata.plist` with a 40-char
   `GitRevision`. Can be added as a fastlane/export assertion step.

## Out of Scope (YAGNI)

- Short hash, dirty-tree flag, branch name — not requested.
- Modifying `service.version` / `CFBundleVersion` — revision is a separate
  attribute by design.
- Android / RN parity — iOS only for now.
