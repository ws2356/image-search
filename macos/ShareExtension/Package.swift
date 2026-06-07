// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShareExtension",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "ShareExtension",
            path: "Sources/ShareExtension"
        )
    ]
)
