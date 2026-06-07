// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeidrunUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HeidrunUI", targets: ["HeidrunUI"])
    ],
    dependencies: [
        .package(path: "../CommonTools"),
        // Keep in lock-step with the HeidrunModules pin — see that
        // file's comment for the `exact:` rationale.
        .package(url: "https://github.com/franckjej/heidrun-protocol.git", exact: "1.0.0-rc21")
    ],
    targets: [
        .target(
            name: "HeidrunUI",
            dependencies: [
                .product(name: "CommonTools", package: "CommonTools"),
                .product(name: "HeidrunCore", package: "heidrun-protocol")
            ],
            resources: [
                .process("Resources"),
                .process("Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "HeidrunUITests",
            dependencies: ["HeidrunUI"]
        )
    ],
    swiftLanguageModes: [.v6]
)
