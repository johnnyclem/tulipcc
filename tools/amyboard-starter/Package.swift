// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AMYboardStarter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AMYboardStarter",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
