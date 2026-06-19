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
        .package(url: "https://github.com/femimarket/swift-project-service", branch: "main"),
    ],
    targets: [
        .target(
            name: "ImageIterate2",
            dependencies: [
                .product(name: "Api", package: "swiftapi"),
                .product(name: "ProjectService", package: "swift-project-service"),
            ],
            path: "Prod",
            exclude: [
                "ProdApp.swift",
                "Assets.xcassets",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
