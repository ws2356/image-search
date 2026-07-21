// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InstantShareKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
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
            targets: ["ISDeviceManagement"]
        ),
    ],
    dependencies: [
        .package(path: "../Common"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
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
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Common", package: "Common"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            resources: []
        ),
        .target(
            name: "ISDeviceManagement",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Common", package: "Common"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            resources: []
        ),
        .testTarget(
            name: "ISFromPCTests",
            dependencies: [
                .target(name: "ISFromPC"),
            ]
        ),
    ]
)
