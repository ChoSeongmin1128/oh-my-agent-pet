import AgentPetClaude
import AgentPetCodex
import AgentPetCore
import AgentPetProviders
import Foundation

struct ApplicationProviderRuntime {
  let adapter: any TaskProviderAdapter
  let connectionInspector: any ProviderConnectionInspecting
}

enum ApplicationProviderCatalog {
  static func runtimes(
    homeDirectory: URL,
    environment: [String: String],
    cliExecutableURL: URL
  ) -> [ApplicationProviderRuntime] {
    let claudePaths = ClaudePaths(homeDirectory: homeDirectory, environment: environment)
    let codexPaths = CodexPaths(homeDirectory: homeDirectory, environment: environment)
    return [
      ApplicationProviderRuntime(
        adapter: ClaudeTaskProvider(paths: claudePaths),
        connectionInspector: ClaudeConnectionInspector(
          homeDirectory: homeDirectory,
          environment: environment,
          executableURL: cliExecutableURL
        )
      ),
      ApplicationProviderRuntime(
        adapter: CodexTaskProvider(paths: codexPaths),
        connectionInspector: CodexConnectionInspector(
          homeDirectory: homeDirectory,
          environment: environment,
          executableURL: cliExecutableURL
        )
      ),
    ]
  }
}
