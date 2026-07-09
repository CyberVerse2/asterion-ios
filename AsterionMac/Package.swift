// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AsterionMac",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "AsterionMac", targets: ["AsterionMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/clerk/clerk-ios", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "AsterionMac",
            dependencies: [
                .product(name: "ClerkKit", package: "clerk-ios"),
                .product(name: "ClerkKitUI", package: "clerk-ios"),
            ],
            path: "Sources/AsterionMac",
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/Brand"),
            ]
        ),
        .testTarget(
            name: "AsterionMacTests",
            dependencies: ["AsterionMac"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
