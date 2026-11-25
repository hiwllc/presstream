// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PressStream",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PressStream",
            path: "Sources/PressStream",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
            ]
        )
    ]
)
