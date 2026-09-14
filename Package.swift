// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DictateBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DictateBar",
            path: "Sources/DictateBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
