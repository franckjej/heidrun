// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeidrunModules",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HeidrunChat",      targets: ["HeidrunChat"]),
        .library(name: "HeidrunAgreement", targets: ["HeidrunAgreement"]),
        .library(name: "HeidrunMessages",  targets: ["HeidrunMessages"]),
        .library(name: "HeidrunNews",      targets: ["HeidrunNews"]),
        .library(name: "HeidrunFiles",     targets: ["HeidrunFiles"]),
        .library(name: "HeidrunAdmin",     targets: ["HeidrunAdmin"]),
        .library(name: "HeidrunBookmarks", targets: ["HeidrunBookmarks"])
    ],
    dependencies: [
        // `exact:` rather than `from:` because pre-release tags compare
        // lexically in SemVer (`"rc10" < "rc9"` since '1' < '9'), so
        // `from: "1.0.0-rc11"` would happily pick rc9 as "newer".
        .package(url: "https://github.com/franckjej/heidrun-protocol.git", exact: "1.0.0-rc16"),
        .package(path: "../HeidrunUI"),
        .package(path: "../CommonTools")
    ],
    targets: [
        .target(
            name: "HeidrunChat",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI"),
                .product(name: "CommonTools", package: "CommonTools")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "HeidrunAgreement",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "HeidrunMessages",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI"),
                .product(name: "CommonTools", package: "CommonTools")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "HeidrunNews",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI"),
                .product(name: "CommonTools", package: "CommonTools")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "HeidrunFiles",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI"),
                .product(name: "CommonTools", package: "CommonTools")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "HeidrunAdmin",
            dependencies: [
                .product(name: "HeidrunCore", package: "heidrun-protocol"),
                .product(name: "HeidrunUI",   package: "HeidrunUI"),
                .product(name: "CommonTools", package: "CommonTools")
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(name: "HeidrunBookmarks", dependencies: [
            .product(name: "HeidrunCore", package: "heidrun-protocol")
        ]),
        .testTarget(name: "HeidrunChatTests",      dependencies: ["HeidrunChat"]),
        .testTarget(name: "HeidrunAgreementTests", dependencies: ["HeidrunAgreement"]),
        .testTarget(name: "HeidrunMessagesTests",  dependencies: ["HeidrunMessages"]),
        .testTarget(name: "HeidrunNewsTests",      dependencies: ["HeidrunNews"]),
        .testTarget(name: "HeidrunFilesTests",     dependencies: ["HeidrunFiles"]),
        .testTarget(name: "HeidrunAdminTests",     dependencies: ["HeidrunAdmin"]),
        .testTarget(name: "HeidrunBookmarksTests", dependencies: ["HeidrunBookmarks"])
    ],
    swiftLanguageModes: [.v6]
)
