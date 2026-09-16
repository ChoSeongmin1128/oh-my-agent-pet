import AgentPetCore

public protocol TaskProviderAdapter: Sendable {
  var identifier: ProviderIdentifier { get }

  func loadTasks() async throws -> [AgentTaskSnapshot]
}
