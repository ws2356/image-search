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
            ],
            resources: []
        ),
    ]
)
