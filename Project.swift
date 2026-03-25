import ProjectDescription

let bundleIdentifier = "dev.zach.mitori"
let deploymentTargets: DeploymentTargets = .macOS("14.0")

let project = Project(
    name: "Mitori",
    targets: [
        .target(
            name: "Mitori",
            destinations: .macOS,
            product: .app,
            bundleId: bundleIdentifier,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Mitori",
                    "LSUIElement": true,
                ]
            ),
            buildableFolders: [
                "Mitori/Sources",
                "Mitori/Resources",
            ],
            dependencies: [
                .external(name: "ApplePackage"),
                .external(name: "KeychainAccess"),
            ]
        ),
        .target(
            name: "MitoriTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundleIdentifier).tests",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            buildableFolders: [
                "Mitori/Tests"
            ],
            dependencies: [
                .target(name: "Mitori"),
                .external(name: "ApplePackage"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "MitoriTests",
            buildAction: .buildAction(targets: ["MitoriTests"]),
            testAction: .targets(["MitoriTests"])
        ),
    ]
)
