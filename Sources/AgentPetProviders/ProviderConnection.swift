import AgentPetCore
import Foundation

public enum ProviderConnectionState: String, Equatable, Sendable {
  case connected
  case notConfigured = "not_configured"
  case needsAttention = "needs_attention"
  case unavailable
}

public struct ProviderConnectionStatus: Equatable, Sendable {
  public let provider: ProviderIdentifier
  public let state: ProviderConnectionState
  public let detailCode: String?

  public init(
    provider: ProviderIdentifier,
    state: ProviderConnectionState,
    detailCode: String? = nil
  ) {
    self.provider = provider
    self.state = state
    self.detailCode = detailCode
  }
}

public protocol ProviderConnectionInspecting: Sendable {
  var identifier: ProviderIdentifier { get }
  func connectionStatus() async -> ProviderConnectionStatus
  func watchedURLs() -> [URL]
}

extension ProviderConnectionInspecting {
  public func watchedURLs() -> [URL] { [] }
}

public struct ProviderConnectionCoordinator: Sendable {
  private let inspectors: [any ProviderConnectionInspecting]

  public init(inspectors: [any ProviderConnectionInspecting]) throws {
    var identifiers = Set<ProviderIdentifier>()
    for inspector in inspectors {
      guard identifiers.insert(inspector.identifier).inserted else {
        throw ProviderCoordinatorError.duplicateProvider(inspector.identifier)
      }
    }
    self.inspectors = inspectors
  }

  public func refresh() async -> [ProviderConnectionStatus] {
    await withTaskGroup(of: ProviderConnectionStatus.self) { group in
      for inspector in inspectors {
        group.addTask { await inspector.connectionStatus() }
      }
      var statuses: [ProviderConnectionStatus] = []
      for await status in group {
        statuses.append(status)
      }
      return statuses.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }
  }
}
