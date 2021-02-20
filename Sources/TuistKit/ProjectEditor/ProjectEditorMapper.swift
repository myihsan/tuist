import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> ValueGraph
}

final class ProjectEditorMapper: ProjectEditorMapping {
    private struct ProjectMappingResult {
        let project: Project
        let targets: [Target]
        let dependencies: [ValueGraphDependency]
    }
    
    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> ValueGraph {
        let swiftVersion = try System.shared.swiftVersion()
        let targetSettings = Settings(
            base: settings(projectDescriptionPath: projectDescriptionPath, swiftVersion: swiftVersion),
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let projectsProjectMapping = mapProjectsProject(
            projectManifests: projectManifests,
            targetSettings: targetSettings,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
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
            destinationDirectory: destinationDirectory,
            tuistPath: tuistPath
        )

        let projectMappings = [projectsProjectMapping, pluginsProjectMapping]
            .compactMap { $0 }

        let workspace = Workspace(
            path: sourceRootPath,
            xcWorkspacePath: destinationDirectory.appending(component: "\(name).xcworkspace"),
            name: name,
            projects: projectMappings.map(\.project.path)
        )

        let graphProjects = projectMappings
            .map { ($0.project.path, $0.project) }

        let graphTargets = projectMappings
            .map { ($0.project.path, $0.targets) }
            .map { path, targets in
                (path, Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) }))
            }

        let graphDependencies = projectMappings
            .flatMap { $0.dependencies }
            .map { dependency -> (ValueGraphDependency, Set<ValueGraphDependency>) in (dependency, []) }

        return ValueGraph(
            name: name,
            path: sourceRootPath,
            workspace: workspace,
            projects: Dictionary(uniqueKeysWithValues: graphProjects),
            packages: [:],
            targets: Dictionary(uniqueKeysWithValues: graphTargets),
            dependencies: Dictionary(uniqueKeysWithValues: graphDependencies)
        )
    }

    private func mapProjectsProject(
        projectManifests: [AbsolutePath],
        targetSettings: Settings,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        tuistPath: AbsolutePath,
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?
    ) -> ProjectMappingResult? {
        guard !projectManifests.isEmpty else { return nil }

        let projectName = "Projects"
        let projectPath = sourceRootPath.appending(component: projectName)
        let manifestsFilesGroup = ProjectGroup.group(name: projectName)

        let helpersTarget: Target? = {
            guard !helpers.isEmpty else { return nil }
            return editorHelperTarget(
                name: Constants.helpersDirectoryName,
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: helpers
            )
        }()

        let templatesTarget: Target? = {
            guard !templates.isEmpty else { return nil }
            return editorHelperTarget(
                name: Constants.templatesDirectoryName,
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

        let optionalManifestTargets = [
            helpersTarget,
            templatesTarget,
            setupTarget,
            configTarget,
            dependenciesTarget
        ].compactMap { $0 }

        let projectManifestTargets = namedProjects(projectManifests).map { name, projectManifestSourcePath -> Target in
            let dependencies = helpersTarget.map { [Dependency.target(name: $0.name)] } ?? []
            return editorHelperTarget(
                name: name,
                filesGroup: manifestsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: [projectManifestSourcePath],
                dependencies: dependencies
            )
        }

        let targets = projectManifestTargets + optionalManifestTargets
        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: projectPath, name: $0.name) })
        let arguments = Arguments(launchArguments: [LaunchArgument(name: "generate --path \(sourceRootPath)", isEnabled: true)])
        let runAction = RunAction(configurationName: "Debug", executable: nil, filePath: tuistPath, arguments: arguments, diagnosticsOptions: Set())
        let scheme = Scheme(name: projectName, shared: true, buildAction: buildAction, runAction: runAction)
        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64"
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let manifestsProject = Project(
            path: projectPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: destinationDirectory.appending(component: "\(projectName).xcodeproj"),
            name: projectName,
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: manifestsFilesGroup,
            targets: targets,
            packages: [],
            schemes: [scheme],
            additionalFiles: []
        )

        let projectDependencies = optionalManifestTargets
            .map { ValueGraphDependency.target(name: $0.name, path: projectPath) }

        return ProjectMappingResult(
            project: manifestsProject,
            targets: targets,
            dependencies: projectDependencies
        )
    }

    private func mapPluginsProject(
        pluginManifests: [AbsolutePath],
        targetSettings: Settings,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        tuistPath: AbsolutePath
    ) -> ProjectMappingResult? {
        guard !pluginManifests.isEmpty else { return nil }

        let projectName = "Plugins"
        let projectPath = sourceRootPath.appending(component: projectName)
        let pluginsFilesGroup = ProjectGroup.group(name: projectName)

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

        let buildAction = BuildAction(targets: pluginTargets.map { TargetReference(projectPath: projectPath, name: $0.name) })
        let scheme = Scheme(name: projectName, shared: true, buildAction: buildAction, runAction: nil)
        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64"
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let pluginsProject = Project(
            path: projectPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: destinationDirectory.appending(component: "\(projectName).xcodeproj"),
            name: projectName,
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: pluginsFilesGroup,
            targets: pluginTargets,
            packages: [],
            schemes: [scheme],
            additionalFiles: []
        )

        return ProjectMappingResult(
            project: pluginsProject,
            targets: pluginTargets,
            dependencies: []
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
    private func namedProjects(_ manifests: [AbsolutePath]) -> [String: AbsolutePath] {
        manifests.reduce(into: [String: AbsolutePath]()) { result, manifest in
            var name = "\(manifest.parentDirectory.basename)Project"
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
            var name = "\(pluginPath.parentDirectory.basename)Plugin"
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
