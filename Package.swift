// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "ImageIterate2",
    platforms: [
        .iOS(.v26),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "ImageIterate2",
            targets: ["ImageIterate2"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/femimarket/swiftapi", branch: "main"),
    ],
    targets: [
        .target(
            name: "ImageIterate2",
            dependencies: [
                .product(name: "Api", package: "swiftapi"),
            ],
            path: "ImageIterate2",
            exclude: [
                "ImageIterate2App.swift",
                "doc.md",
                "Assets.xcassets",
            ],
            resources: [
                .process("demoUploadSong_019e7f3d-aa21-7173-86ae-fbe8d61d0a84.png"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
