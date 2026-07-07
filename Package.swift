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
        .library(
            name: "Prod",
            targets: ["Prod"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/femimarket/api", branch: "main"),
    ],
    targets: [
        .target(
            name: "ImageIterate2",
            dependencies: [
                .product(name: "Api", package: "api"),
            ],
            path: "ImageIterate2",
            exclude: [
                "ImageIterate2App.swift",
                "doc.md",
                "v1.md",
                "Assets.xcassets",
            ],
            resources: [
                .process("demoUploadSong_019e7f3d-aa21-7173-86ae-fbe8d61d0a84.png"),
            ]
        ),
        .target(
            name: "Prod",
            dependencies: [
                .product(name: "Api", package: "api"),
            ],
            path: "Prod",
            exclude: [
                "ProdApp.swift",
                "Assets.xcassets",
            ]
        ),
        .testTarget(
            name: "ProdTests",
            dependencies: [
                "Prod",
                .product(name: "Api", package: "api"),
            ],
            path: "Tests/ProdTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
