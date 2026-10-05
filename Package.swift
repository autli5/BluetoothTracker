// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "blts_tracker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "blts_tracker",
            targets: ["blts_tracker"]
        )
    ],
    targets: [
        .executableTarget(
            name: "blts_tracker",
            path: "Sources/blts_tracker"
        )
    ]
)
