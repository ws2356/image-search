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
    ],
    targets: [
        .testTarget(
            name: "InstantShareTests",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "ISFromMobile", package: "InstantShareKit"),
                .product(name: "ISFromPC", package: "InstantShareKit"),
                .product(name: "ISDeviceManagement", package: "InstantShareKit"),
            ]
        ),
    ]
)
