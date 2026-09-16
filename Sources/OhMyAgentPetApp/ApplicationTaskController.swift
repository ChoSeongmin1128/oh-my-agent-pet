import AgentPetClaude
import AgentPetProviders
import AgentPetUI
import Foundation

@MainActor
final class ApplicationTaskController {
  private let statusMenuController: StatusMenuController
  private let coordinator: ProviderCoordinator
  private var watcher: ClaudeEventLogWatcher?
  private var refreshInProgress = false
  private var refreshPending = false

  init(
    statusMenuController: StatusMenuController,
    homeDirectory: URL,
    environment: [String: String]
  ) throws {
    self.statusMenuController = statusMenuController
    let paths = ClaudePaths(homeDirectory: homeDirectory, environment: environment)
    let provider = ClaudeTaskProvider(paths: paths)
    coordinator = try ProviderCoordinator(adapters: [provider])
    watcher = ClaudeEventLogWatcher(eventsURL: paths.eventsURL) { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
  }

  func start() throws {
    try watcher?.start()
    requestRefresh()
  }

  func stop() {
    watcher?.stop()
  }

  private func requestRefresh() {
    refreshPending = true
    guard !refreshInProgress else { return }
    refreshInProgress = true

    Task { @MainActor [weak self] in
      guard let self else { return }
      while self.refreshPending {
        self.refreshPending = false
        let report = await self.coordinator.refresh()
        self.statusMenuController.update(representative: report.representative)
      }
      self.refreshInProgress = false
    }
  }
}
