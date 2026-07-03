// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InstantShareKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15),
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
        .library(
            name: "ISDeviceManagement",
            type: .dynamic,
            targets: ["ISDeviceManagement"]
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
                .product(name: "Factory", package: "Factory"),
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
        .target(
            name: "ISDeviceManagement",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Common", package: "Common"),
            ],
            resources: []
        ),
    ]
)
