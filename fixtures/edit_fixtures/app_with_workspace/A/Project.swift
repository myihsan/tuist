import ProjectDescription

let project = Project(
    name: "A",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "A",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.a",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Source/**"]
        )
    ]
)
