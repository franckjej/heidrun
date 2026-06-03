// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
    .unsafeFlags(["-enable-library-evolution"])
]

let package = Package(
    name: "CommonTools",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CommonTools",
            targets: ["CommonTools"])
    ],
    dependencies: [ ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CommonTools",
            dependencies: []
        ),
        .testTarget(
            name: "CommonToolsTests",
            dependencies: ["CommonTools"]
        )
    ]
)
let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
    .unsafeFlags(["-enable-library-evolution"])
]

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: swiftSettings)
    target.swiftSettings = settings
}
