// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RsyncMyFootages",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "RsyncMyFootages",
            path: "Sources/RsyncMyFootages",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "RsyncMyFootagesTests",
            dependencies: ["RsyncMyFootages"],
            path: "Tests/RsyncMyFootagesTests"
        ),
    ]
)
