// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "Mitori",
    dependencies: [
        .package(
            url: "https://github.com/Zach677/ApplePackage.git",
            revision: "6925a6c2459aa649d223051bc6e561cb8b31b2d4"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            exact: "4.2.2"
        ),
    ]
)
