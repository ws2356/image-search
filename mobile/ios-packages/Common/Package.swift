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
