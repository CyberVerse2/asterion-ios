// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AsterionDevice",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "AsterionDevice", targets: ["AsterionDevice"]),
    ],
    targets: [
        .target(
            name: "DeviceBuilderCore",
            path: "Sources/DeviceBuilderCore"
        ),
        .executableTarget(
            name: "AsterionDevice",
            dependencies: ["DeviceBuilderCore"],
            path: "Sources/AsterionDevice"
        ),
        .testTarget(
            name: "DeviceBuilderCoreTests",
            dependencies: ["DeviceBuilderCore"],
            path: "Tests/DeviceBuilderCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
