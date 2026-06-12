// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncMyFootages",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SyncMyFootages",
            path: "Sources/SyncMyFootages",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "SyncMyFootagesTests",
            dependencies: ["SyncMyFootages"],
            path: "Tests/SyncMyFootagesTests"
        ),
    ]
)
