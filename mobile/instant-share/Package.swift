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
    targets: []
)
