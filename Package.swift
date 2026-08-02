// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetPulse",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "NetPulse",
            path: "Sources/NetPulse",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
