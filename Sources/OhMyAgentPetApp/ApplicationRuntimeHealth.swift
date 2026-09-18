import AgentPetCore
import AgentPetProviders

@MainActor
final class ApplicationRuntimeHealth {
  private(set) var providerConnections: [ProviderIdentifier: ProviderConnectionStatus] = [:]
  private(set) var providerFailures: [ProviderFailure] = []
  private(set) var petLibraryPrepareFailed = false
  private(set) var taskControllerStartFailed = false

  var connectedProviderCount: Int {
    providerConnections.values.count { $0.state == .connected }
  }

  func updateConnections(_ statuses: [ProviderConnectionStatus]) {
    providerConnections = Dictionary(uniqueKeysWithValues: statuses.map { ($0.provider, $0) })
  }

  func updateProviderFailures(_ failures: [ProviderFailure]) {
    providerFailures = failures
  }

  func recordPetLibraryPrepareFailure() {
    petLibraryPrepareFailed = true
  }

  func recordTaskControllerStartFailure() {
    taskControllerStartFailed = true
  }
}
