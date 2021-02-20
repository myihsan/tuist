import ProjectDescription

let workspace = Workspace(
    name: "Projects",
    projects: [
        .relativeToManifest("A"),
        .relativeToManifest("B")
    ]
)
