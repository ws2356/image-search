// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShareExtension",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0")
    ],
    targets: [
        .executableTarget(
            name: "ShareExtension",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ],
            path: "Sources/ShareExtension",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
