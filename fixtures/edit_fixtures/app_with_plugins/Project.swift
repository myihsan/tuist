import HelpersA
import HelpersB
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
    name: "TuistPluginTest",
    platform: .iOS,
    additionalTargets: [
        Project.helperA,
        Project.helperB
    ]
)
