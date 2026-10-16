// swift-tools-version: 6.2

import PackageDescription

/// Asterion's pure, UI-free logic: catalog models, reading and playback
/// progress, and the policies built on them. Foundation only, so the tests
/// run on the Mac with `swift test` without a simulator.
let package = Package(
    name: "AsterionKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "AsterionKit", targets: ["AsterionKit"]),
    ],
    targets: [
        .target(name: "AsterionKit"),
        .testTarget(name: "AsterionKitTests", dependencies: ["AsterionKit"]),
    ]
)
