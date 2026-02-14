// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RAMBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "RAMBarLib",
            path: "RAMBarLib"
        ),
        .testTarget(
            name: "RAMBarTests",
            dependencies: ["RAMBarLib"],
            path: "RAMBarTests"
        ),
    ]
)
