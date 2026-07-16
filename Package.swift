// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipboardOverlay",
            path: "Sources/ClipboardOverlay"
        )
    ]
)
