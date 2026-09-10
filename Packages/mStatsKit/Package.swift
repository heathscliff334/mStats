// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mStatsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "mStatsKit", targets: ["mStatsKit"])
    ],
    targets: [
        .target(
            name: "CSystemShims",
            path: "Sources/CSystemShims"
        ),
        .target(
            name: "mStatsKit",
            dependencies: ["CSystemShims"],
            path: "Sources/mStatsKit"
        ),
        .testTarget(
            name: "mStatsKitTests",
            dependencies: ["mStatsKit"],
            path: "Tests/mStatsKitTests"
        )
    ]
)
