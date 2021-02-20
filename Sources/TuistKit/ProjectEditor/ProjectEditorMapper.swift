import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> Graph
}

final class ProjectEditorMapper: ProjectEditorMapping {
    private struct ProjectMappingResult {
        let project: Project
        let targetNodes: [TargetNode]
        let dependencyNodes: [TargetNode]
    }

    private let manifestLoader: ManifestLoading

    init(
        manifestLoader: ManifestLoading = ManifestLoader()
    ) {
        self.manifestLoader = manifestLoader
    }

    func map(
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> Graph {
        let swiftVersion = try System.shared.swiftVersion()
        let targetSettings = Settings(
            base: settings(projectDescriptionPath: projectDescriptionPath, swiftVersion: swiftVersion),
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let manifestsProjectMapping = mapManifestsProject(
            projectManifests: projectManifests,
            targetSettings: targetSettings,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            tuistPath: tuistPath,
            helpers: helpers,
            templates: templates,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath
        )

        let pluginsProjectMapping = mapPluginsProject(
            pluginManifests: pluginManifests,
            targetSettings: targetSettings,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            tuistPath: tuistPath
        )

        let workspace = Workspace(
            path: sourceRootPath,
            xcWorkspacePath: sourceRootPath.appending(component: "Manifests.xcworkspace"),
            name: "Manifests",
            projects: [
                manifestsProjectMapping.project.path,
                pluginsProjectMapping.project.path
            ]
        )

        let graphEntryNodes = manifestsProjectMapping.targetNodes +
            pluginsProjectMapping.targetNodes

        let graphTargets = manifestsProjectMapping.targetNodes +
            manifestsProjectMapping.dependencyNodes +
            pluginsProjectMapping.targetNodes +
            pluginsProjectMapping.dependencyNodes

        return Graph(
            name: "Manifests",
            entryPath: sourceRootPath,
            entryNodes: graphEntryNodes,
            workspace: workspace,
            projects: [
                manifestsProjectMapping.project,
                pluginsProjectMapping.project
            ],
            cocoapods: [],
            packages: [],
            precompiled: [],
            targets: [sourceRootPath: graphTargets]
        )
    }

    private func mapManifestsProject(
        projectManifests: [AbsolutePath],
        targetSettings: Settings,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        tuistPath: AbsolutePath,
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?
    ) -> ProjectMappingResult {
        let manifestsFilesGroup = ProjectGroup.group(name: "Manifests")
        let projectManifestDependencies: [Dependency] = helpers.isEmpty ? [] : [.target(name: "ProjectDescriptionHelpers")]

        let projectManifestTargets = namedManifests(projectManifests).map { name, projectManifestSourcePath in
            editorHelperTarget(
                name: name,
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [projectManifestSourcePath],
                dependencies: projectManifestDependencies
            )
        }

        let helpersTarget: Target? = {
            guard !helpers.isEmpty else { return nil }
            return editorHelperTarget(
                name: "ProjectDescriptionHelpers",
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: helpers
            )
        }()

        let templatesTarget: Target? = {
            guard !templates.isEmpty else { return nil }
            return editorHelperTarget(
                name: "Templates",
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: templates
            )
        }()

        let setupTarget: Target? = {
            guard let setupPath = setupPath else { return nil }
            return editorHelperTarget(
                name: "Setup",
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [setupPath]
            )
        }()

        let configTarget: Target? = {
            guard let configPath = configPath else { return nil }
            return editorHelperTarget(
                name: "Config",
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [configPath]
            )
        }()

        let dependenciesTarget: Target? = {
            guard let dependenciesPath = dependenciesPath else { return nil }
            return editorHelperTarget(
                name: "Dependencies",
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [dependenciesPath]
            )
        }()

        let optionalManifestProjectTargets = [
            helpersTarget,
            templatesTarget,
            setupTarget,
            configTarget,
            dependenciesTarget
        ].compactMap { $0 }

        let targets = projectManifestTargets + optionalManifestProjectTargets
        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: sourceRootPath, name: $0.name) })
        let arguments = Arguments(launchArguments: [LaunchArgument(name: "generate --path \(sourceRootPath)", isEnabled: true)])
        let runAction = RunAction(configurationName: "Debug", executable: nil, filePath: tuistPath, arguments: arguments, diagnosticsOptions: Set())
        let scheme = Scheme(name: "Manifests", shared: true, buildAction: buildAction, runAction: runAction)

        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64"
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let manifestsProject = Project(
            path: sourceRootPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: "Manifests",
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: manifestsFilesGroup,
            targets: targets,
            packages: [],
            schemes: [scheme],
            additionalFiles: []
        )

        let dependencyNodes = optionalManifestProjectTargets.map {
            TargetNode(project: manifestsProject, target: $0, dependencies: [])
        }

        let projectManifestTargetNodes = projectManifestTargets.map {
            TargetNode(project: manifestsProject, target: $0, dependencies: dependencyNodes)
        }

        return ProjectMappingResult(
            project: manifestsProject,
            targetNodes: projectManifestTargetNodes,
            dependencyNodes: dependencyNodes
        )
    }

    private func mapPluginsProject(
        pluginManifests: [AbsolutePath],
        targetSettings: Settings,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        tuistPath: AbsolutePath
    ) -> ProjectMappingResult {
        let pluginsFilesGroup = ProjectGroup.group(name: "Plugins")

        let pluginTargets = namedPlugins(pluginManifests).map { name, pluginManifestPath -> Target in
            let helperPaths = FileHandler.shared.glob(pluginManifestPath.parentDirectory, glob: "**/*.swift")
            return editorHelperTarget(
                name: name,
                filesGroup: pluginsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [pluginManifestPath] + helperPaths,
                dependencies: []
            )
        }

        let targetReferences = pluginTargets.map { TargetReference(projectPath: sourceRootPath, name: $0.name) }
        let buildAction = BuildAction(targets: targetReferences)
        let scheme = Scheme(name: "Plugins", shared: true, buildAction: buildAction, runAction: nil)
        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64"
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let pluginsProject = Project(
            path: sourceRootPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: "Plugins",
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: pluginsFilesGroup,
            targets: pluginTargets,
            packages: [],
            schemes: [scheme],
            additionalFiles: []
        )

        let pluginTargetNodes = pluginTargets.map {
            TargetNode(project: pluginsProject, target: $0, dependencies: [])
        }

        return ProjectMappingResult(
            project: pluginsProject,
            targetNodes: pluginTargetNodes,
            dependencyNodes: []
        )
    }

    /// It returns the build settings that should be used in the manifests target.
    /// - Parameter projectDescriptionPath: Path to the ProjectDescription framework.
    /// - Parameter swiftVersion: The system's Swift version.
    private func settings(projectDescriptionPath: AbsolutePath, swiftVersion: String) -> SettingsDictionary {
        let frameworkParentDirectory = projectDescriptionPath.parentDirectory
        var buildSettings = SettingsDictionary()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["LIBRARY_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_INCLUDE_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_VERSION"] = .string(swiftVersion)
        return buildSettings
    }

    /// It returns a dictionary with unique name as key for each Manifest file
    /// - Parameter manifests: Manifest files to assign an unique name
    /// - Returns: Dictionary composed by unique name as key and Manifest file as value.
    private func namedManifests(_ manifests: [AbsolutePath]) -> [String: AbsolutePath] {
        manifests.reduce(into: [String: AbsolutePath]()) { result, manifest in
            var name = "\(manifest.parentDirectory.basename)Manifests"
            while result[name] != nil {
                name = "_\(name)"
            }
            result[name] = manifest
        }
    }

    /// It returns a dictionary with plugin name as key and path to manifest as value.
    /// - Parameter plugins: The list of plugin manifests
    /// - Returns: Dictionary with plugin name as key and path to manifest as value.
    private func namedPlugins(_ plugins: [AbsolutePath]) -> [String: AbsolutePath] {
        plugins.reduce(into: [String: AbsolutePath]()) { result, pluginPath in
            guard let pluginManifest = try? manifestLoader.loadPlugin(at: pluginPath.parentDirectory) else {
                return
            }

            var name = pluginManifest.name
            while result[name] != nil {
                name = "_\(name)"
            }
            result[name] = pluginPath
        }
    }

    /// It returns a target for edit project.
    /// - Parameters:
    ///   - name: Name for the target.
    ///   - filesGroup: File group for target.
    ///   - targetSettings: Target's settings.
    ///   - sourcePaths: Target's sources.
    ///   - dependencies: Target's dependencies.
    /// - Returns: Target for edit project.
    private func editorHelperTarget(
        name: String,
        filesGroup: ProjectGroup,
        targetSettings: Settings,
        sourcePaths: [AbsolutePath],
        dependencies: [Dependency] = []
    ) -> Target {
        Target(name: name,
               platform: .macOS,
               product: .staticFramework,
               productName: name,
               bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
               settings: targetSettings,
               sources: sourcePaths.map { SourceFile(path: $0, compilerFlags: nil) },
               filesGroup: filesGroup,
               dependencies: dependencies)
    }
}
