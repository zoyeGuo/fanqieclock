// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fanqie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "fanqie",
            targets: ["fanqie"]
        )
    ],
    targets: [
        .executableTarget(
            name: "fanqie"
        ),
    ]
)
