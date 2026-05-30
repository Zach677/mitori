// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Mitori",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Mitori", targets: ["Mitori"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Zach677/ApplePackage.git",
            revision: "6925a6c2459aa649d223051bc6e561cb8b31b2d4"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            exact: "4.2.2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Mitori",
            dependencies: [
                "ApplePackage",
                "KeychainAccess",
            ],
            path: "Mitori",
            exclude: [
                "Resources/Info.plist",
                "Tests",
            ],
            sources: [
                "Sources",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MitoriTests",
            dependencies: [
                "Mitori",
            ],
            path: "Mitori/Tests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
