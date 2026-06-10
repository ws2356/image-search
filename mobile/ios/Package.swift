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
            targets: ["AlbumTransporterKit"]
        ),
        .library(
            name: "Common",
            targets: ["Common"]
        ),
        .library(
            name: "ISFromPC",
            targets: ["ISFromPC"]
        ),
        .library(
            name: "ISFromMobile",
            targets: ["ISFromMobile"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.12"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    ],
    targets: [
        .target(
            name: "AlbumTransporterKit",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                "Common",
                "ISFromPC",
                "ISFromMobile"
            ],
            resources: []
        ),
        .target(name: "Common",
               dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
               ],
               resources: []),
        .target(name: "ISFromPC",
               dependencies: ["Common"],
               resources: []),
        .target(name: "ISFromMobile",
               dependencies: [
                "Common"
               ],
               resources: []),
        .testTarget(
            name: "AlbumTransporterKitTests",
            dependencies: [
                "AlbumTransporterKit",
                "Common",
                "ISFromPC",
                "ISFromMobile",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ]
        ),
    ]
)
