import AgentPetCore
import Foundation

public protocol TaskProviderAdapter: Sendable {
  var identifier: ProviderIdentifier { get }

  func loadTasks() async throws -> [AgentTaskSnapshot]
  func watchedURLs() async -> [URL]
}

extension TaskProviderAdapter {
  public func watchedURLs() async -> [URL] { [] }
}
