// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clipboard",
            path: "Sources/Clipboard"
        )
    ]
)
