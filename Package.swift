// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreshMyMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FreshMyMac",
            path: "Sources/FreshMyMac"
        )
    ]
)
