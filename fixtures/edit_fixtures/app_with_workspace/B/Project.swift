import ProjectDescription

let project = Project(
    name: "B",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "B",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.b",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Source/**"]
        )
    ]
)
