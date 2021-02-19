import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting

@testable import TuistCoreTesting
@testable import TuistKit

final class MockProjectEditorMapper: ProjectEditorMapping {
    var mapStub: ([Project], Graph)?
    var mapArgs: [(
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
    )] = []

    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             xcodeProjPath: AbsolutePath,
             setupPath: AbsolutePath?,
             configPath: AbsolutePath?,
             dependenciesPath: AbsolutePath?,
             projectManifests: [AbsolutePath],
             pluginManifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) -> ([Project], Graph)
    {
        mapArgs.append((tuistPath: tuistPath,
                        sourceRootPath: sourceRootPath,
                        xcodeProjPath: xcodeProjPath,
                        setupPath: setupPath,
                        configPath: configPath,
                        dependenciesPath: dependenciesPath,
                        projectManifests: projectManifests,
                        pluginManifests: pluginManifests,
                        helpers: helpers,
                        templates: templates,
                        projectDescriptionPath: projectDescriptionPath))
        if let mapStub = mapStub { return mapStub }
        return ([Project.test()], Graph.test())
    }
}
