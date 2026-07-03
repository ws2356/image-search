# Split Instant Share Into Separate iOS App

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract instant-share code (ISFromMobile, ISFromPC, Common) from `mobile/ios/` into shared SPM packages under `mobile/ios-packages/`, then create a standalone `mobile/instant-share/` iOS app project.

**Architecture:** Two new SPM packages — `Common` (infrastructure layer: identity, keychain, TLS, fonts, shared views) and `InstantShareKit` (feature layer: ISFromMobile, ISFromPC). Both existing `mobile/ios/` and new `mobile/instant-share/` projects reference them as local path dependencies. App group and keychain sharing use the same team ID so auth data is shared.

**Tech Stack:** Swift 6, SwiftPM, iOS 15+, ComposableArchitecture, Factory, OpenTelemetry

## Global Constraints

- All SPM packages target iOS 15+
- Keep forward slash file paths for consistency
- App group: `group.com.aubackup.instant-share` (same as current ShareExtension)
- Keychain access group: `$(AppIdentifierPrefix)net.boldman.albumtransporter` (same as current)
- Team ID: ZU6V838VRQ (from existing project)
- Commit after every task with a descriptive message

---

### Task 1: Create Common SPM Package

**Files:**
- Create: `mobile/ios-packages/Common/Package.swift`
- Create: `mobile/ios-packages/Common/Sources/Common/` (directory)
- Move: all files from `mobile/ios/Sources/Common/` → `mobile/ios-packages/Common/Sources/Common/`

**Interfaces:**
- Produces: `Common` library product with targets for DI, Services, Utilities, Views, Resources (fonts)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/Common
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/Common/Sources
```

- [ ] **Step 2: Create Package.swift for Common**

The dependencies are: Factory, OpenTelemetryApi, OpenTelemetrySdk, SwiftASN1, X509 (same as current Common target).

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Common",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "Common",
            type: .dynamic,
            targets: ["Common"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
```

- [ ] **Step 3: Move Common source files**

```bash
cp -R /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/Common/* /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/Common/Sources/
```

- [ ] **Step 4: Remove old Common source directory**

```bash
rm -rf /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/Common
```

- [ ] **Step 5: Verify structure**

```bash
ls /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/Common/Sources/Common/
```
Should show: DI/, Resources/, Services/, Utilities/, Views/

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: extract Common into shared SPM package at mobile/ios-packages/Common"
```

---

### Task 2: Create InstantShareKit SPM Package

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Package.swift`
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/` (directory)
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/` (directory)
- Move: all files from `mobile/ios/Sources/ISFromMobile/` → `mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/`
- Move: all files from `mobile/ios/Sources/ISFromPC/` → `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/InstantShareKit
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/InstantShareKit/Sources
```

- [ ] **Step 2: Create Package.swift for InstantShareKit**

Dependencies: Common (local), Factory, ComposableArchitecture (TCA). Common is a local path dependency. ISFromPC depends only on Common. ISFromMobile depends on Factory, ComposableArchitecture, and Common.

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InstantShareKit",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "ISFromPC",
            type: .dynamic,
            targets: ["ISFromPC"]
        ),
        .library(
            name: "ISFromMobile",
            type: .dynamic,
            targets: ["ISFromMobile"]
        ),
    ],
    dependencies: [
        .package(path: "../Common"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "ISFromPC",
            dependencies: [
                .product(name: "Common", package: "Common"),
            ],
            resources: []
        ),
        .target(
            name: "ISFromMobile",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Common", package: "Common"),
            ],
            resources: []
        ),
    ]
)
```

- [ ] **Step 3: Move ISFromMobile source files**

```bash
cp -R /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/ISFromMobile/* /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/InstantShareKit/Sources/
```

- [ ] **Step 4: Move ISFromPC source files**

```bash
cp -R /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/ISFromPC/* /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/InstantShareKit/Sources/
```

- [ ] **Step 5: Remove old source directories**

```bash
rm -rf /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/ISFromMobile
rm -rf /Users/ws2356/dev/ausearch-release/src/mobile/ios/Sources/ISFromPC
```

- [ ] **Step 6: Verify structure**

```bash
ls /Users/ws2356/dev/ausearch-release/src/mobile/ios-packages/InstantShareKit/Sources/
```
Should show: ISFromMobile/, ISFromPC/

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "refactor: extract InstantShareKit into shared SPM package at mobile/ios-packages/InstantShareKit"
```

---

### Task 3: Update mobile/ios/Package.swift to Depend on New Packages

**Files:**
- Modify: `mobile/ios/Package.swift`

- [ ] **Step 1: Rewrite mobile/ios/Package.swift**

Replace local targets for Common, ISFromMobile, ISFromPC with package dependencies pointing to `../ios-packages/Common` and `../ios-packages/InstantShareKit`. The AlbumTransporterKit target changes its `"Common"`, `"ISFromPC"`, `"ISFromMobile"` string dependencies to `.product(name:)` form.

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AlbumTransporterKit",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "AlbumTransporterKit",
            type: .dynamic,
            targets: ["AlbumTransporterKit"]
        ),
    ],
    dependencies: [
        .package(path: "../ios-packages/Common"),
        .package(path: "../ios-packages/InstantShareKit"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "AlbumTransporterKit",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "Common", package: "Common"),
                .product(name: "ISFromPC", package: "InstantShareKit"),
                .product(name: "ISFromMobile", package: "InstantShareKit"),
            ],
            resources: []
        ),
    ]
)
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "refactor: update mobile/ios/Package.swift to use shared packages"
```

---

### Task 4: Update mobile/ios Xcode Project for New Package References

**Files:**
- Modify: `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add XCLocalSwiftPackageReference entries**

Insert two new entries in the `XCLocalSwiftPackageReference` section:
- `FAKECOMMON000000000001` for `../ios-packages/Common`
- `FAKEISHK00000000000001` for `../ios-packages/InstantShareKit`

- [ ] **Step 2: Add XCSwiftPackageProductDependency entries**

Insert three new entries:
- `FAKECOMMON000000000002` for Common product from Common package
- `FAKEISHK000000000002` for ISFromMobile product from InstantShareKit package
- `FAKEISHK000000000003` for ISFromPC product from InstantShareKit package

- [ ] **Step 3: Update target packageProductDependencies**

AlbumTransporterApp target: add Common, ISFromMobile, ISFromPC
ShareExtension target: add Common, ISFromMobile
AlbumTransporterAppSnapshotTests target: no change needed (it depends on AlbumTransporterKit which transitively provides everything)

- [ ] **Step 4: Verify**

Open the project in Xcode and ensure the package resolution succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: update Xcode project with new package references"
```

---

### Task 5: Create instant-share App Project Shell

**Files:**
- Create: `mobile/instant-share/Package.swift`
- Create: `mobile/instant-share/App/AlbumTransporterApp.swift`
- Create: `mobile/instant-share/App/Info.plist`
- Create: `mobile/instant-share/App/Assets.xcassets/Contents.json`
- Create: `mobile/instant-share/App/AlbumTransporterApp.entitlements`
- Create: `mobile/instant-share/App/LaunchScreen.storyboard`
- Create: `mobile/instant-share/.gitignore`
- Create: `mobile/instant-share/buildServer.json`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/instant-share/App
```

- [ ] **Step 2: Create Package.swift**

The instant-share app's Package.swift defines no targets — it only exists so the Xcode project can reference the local packages. The app code lives in App/ which is compiled directly by Xcode.

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InstantShare",
    platforms: [
        .iOS(.v15),
    ],
    dependencies: [
        .package(path: "../ios-packages/Common"),
        .package(path: "../ios-packages/InstantShareKit"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    ],
    targets: [
        // App target is defined in Xcode, not here
    ]
)
```

- [ ] **Step 3: Create App entry point**

```swift
// AlbumTransporterApp.swift
import Common
import SwiftUI

@main
struct InstantShareApp: App {
    init() {
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                FlowView(
                    store: Store(initialState: FlowFeature.State()) {
                        FlowFeature()
                    }
                )
            }
        }
    }
}
```

- [ ] **Step 4: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>Instant Share</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>NSBonjourServices</key>
    <array>
        <string>_instantshare._tcp</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Instant Share connects directly to your desktop on the local network for file transfer.</string>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Create entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.aubackup.instant-share</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)net.boldman.albumtransporter</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 6: Create Assets.xcassets Contents.json**

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 7: Create .gitignore**

```
.DS_Store
*.xcuserdata
*.xcworkspace/xcuserdata
DerivedData/
.build/
```

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: create instant-share app project shell"
```

---

### Task 6: Create instant-share Xcode Project

**Files:**
- Create: `mobile/instant-share/InstantShare.xcodeproj/project.pbxproj`

This is the most complex task. The Xcode project needs:
- App target (net.boldman.instantshare)
- ShareExtension target (app extension)
- Local package references to Common and InstantShareKit
- Product dependencies for Common, ISFromMobile, ISFromPC
- Build settings matching the existing project (team, version, etc.)

The pbxproj is created from a template adapted from the existing `mobile/ios/AlbumTransporterApp.xcodeproj/project.pbxproj`.

- [ ] **Step 1: Create project directory**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/instant-share/InstantShare.xcodeproj
```

- [ ] **Step 2: Create project.pbxproj**

(Create adapted from existing template, with new UUIDs, new bundle IDs, and local package references pointing to `../ios-packages/Common` and `../ios-packages/InstantShareKit`)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: create instant-share Xcode project"
```

---

### Task 7: Create instant-share ShareExtension

**Files:**
- Create: `mobile/instant-share/ShareExtension/ShareViewController.swift`
- Create: `mobile/instant-share/ShareExtension/Info.plist`
- Create: `mobile/instant-share/ShareExtension/ShareExtension.entitlements`

- [ ] **Step 1: Create directory**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/instant-share/ShareExtension
```

- [ ] **Step 2: Copy and adapt ShareExtension from mobile/ios**

Copy `ShareViewController.swift`, `Info.plist`, `ShareExtension.entitlements` from `mobile/ios/ShareExtension/`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add ShareExtension to instant-share app"
```

---

### Task 8: Add fastlane config to instant-share project

**Files:**
- Create: `mobile/instant-share/fastlane/Fastfile`
- Create: `mobile/instant-share/fastlane/Appfile`
- Create: `mobile/instant-share/fastlane/README.md`

- [ ] **Step 1: Create fastlane directory**

```bash
mkdir -p /Users/ws2356/dev/ausearch-release/src/mobile/instant-share/fastlane
```

- [ ] **Step 2: Create Fastfile and Appfile**

(A basic fastlane setup for building and deploying the instant-share app.)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: add fastlane config for instant-share app"
```
