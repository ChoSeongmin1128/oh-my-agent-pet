import AgentPetCore
import Foundation

public enum ProviderCoordinatorError: Error, Equatable, Sendable {
  case duplicateProvider(ProviderIdentifier)
}

public enum ProviderFailureReason: String, Equatable, Sendable {
  case loadFailed
  case mismatchedProvider
  case duplicateTaskIdentity
}

public struct ProviderFailure: Equatable, Sendable {
  public let provider: ProviderIdentifier
  public let reason: ProviderFailureReason

  public init(provider: ProviderIdentifier, reason: ProviderFailureReason) {
    self.provider = provider
    self.reason = reason
  }
}

public struct ProviderRefreshReport: Sendable {
  public let tasks: [AgentTaskSnapshot]
  public let representative: RepresentativeTask?
  public let failures: [ProviderFailure]

  public init(
    tasks: [AgentTaskSnapshot],
    representative: RepresentativeTask?,
    failures: [ProviderFailure]
  ) {
    self.tasks = tasks
    self.representative = representative
    self.failures = failures
  }
}

public struct ProviderCoordinator: Sendable {
  private let adapters: [any TaskProviderAdapter]
  private let selector: RepresentativeTaskSelector

  public init(
    adapters: [any TaskProviderAdapter],
    selector: RepresentativeTaskSelector = RepresentativeTaskSelector()
  ) throws {
    var identifiers = Set<ProviderIdentifier>()
    for adapter in adapters {
      guard identifiers.insert(adapter.identifier).inserted else {
        throw ProviderCoordinatorError.duplicateProvider(adapter.identifier)
      }
    }
    self.adapters = adapters
    self.selector = selector
  }

  public func refresh() async -> ProviderRefreshReport {
    let loads = await withTaskGroup(of: AdapterLoad.self, returning: [AdapterLoad].self) { group in
      for adapter in adapters {
        group.addTask {
          do {
            return AdapterLoad(
              provider: adapter.identifier,
              result: .success(try await adapter.loadTasks())
            )
          } catch {
            return AdapterLoad(
              provider: adapter.identifier,
              result: .failure
            )
          }
        }
      }

      var results: [AdapterLoad] = []
      for await result in group {
        results.append(result)
      }
      return results
    }

    var tasks: [AgentTaskSnapshot] = []
    var failures: [ProviderFailure] = []

    for load in loads.sorted(by: { $0.provider.rawValue < $1.provider.rawValue }) {
      switch load.result {
      case .success(let loadedTasks):
        if loadedTasks.contains(where: { $0.identity.provider != load.provider }) {
          failures.append(
            ProviderFailure(
              provider: load.provider,
              reason: .mismatchedProvider
            )
          )
        } else if Set(loadedTasks.map(\.identity)).count != loadedTasks.count {
          failures.append(
            ProviderFailure(
              provider: load.provider,
              reason: .duplicateTaskIdentity
            )
          )
        } else {
          tasks.append(contentsOf: loadedTasks)
        }
      case .failure:
        failures.append(ProviderFailure(provider: load.provider, reason: .loadFailed))
      }
    }

    tasks.sort { $0.identity.stableKey < $1.identity.stableKey }
    return ProviderRefreshReport(
      tasks: tasks,
      representative: selector.select(from: tasks),
      failures: failures
    )
  }
}

private struct AdapterLoad: Sendable {
  enum Result: Sendable {
    case success([AgentTaskSnapshot])
    case failure
  }

  let provider: ProviderIdentifier
  let result: Result
}
