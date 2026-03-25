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
            url: "https://github.com/Lakr233/ApplePackage.git",
            revision: "fd4860b78eb2db60a0dcbe7e5a6e4a3d2cae004e"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            exact: "4.2.2"
        ),
    ]
)
