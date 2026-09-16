import AgentPetClaude
import AgentPetCodex
import AgentPetEvents
import AgentPetProviders
import AgentPetUI
import Foundation

@MainActor
final class ApplicationTaskController {
  private let statusMenuController: StatusMenuController
  private let coordinator: ProviderCoordinator
  private let codexProvider: CodexTaskProvider
  private let codexPaths: CodexPaths
  private var eventWatcher: AgentEventLogWatcher?
  private var codexWatcher: CodexFileSetWatcher?
  private var refreshInProgress = false
  private var refreshPending = false

  init(
    statusMenuController: StatusMenuController,
    homeDirectory: URL,
    environment: [String: String]
  ) throws {
    self.statusMenuController = statusMenuController
    let claudePaths = ClaudePaths(homeDirectory: homeDirectory, environment: environment)
    let claudeProvider = ClaudeTaskProvider(paths: claudePaths)
    codexPaths = CodexPaths(homeDirectory: homeDirectory, environment: environment)
    codexProvider = CodexTaskProvider(paths: codexPaths)
    coordinator = try ProviderCoordinator(adapters: [claudeProvider, codexProvider])
    eventWatcher = AgentEventLogWatcher(eventsURL: claudePaths.eventsURL) { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
    codexWatcher = CodexFileSetWatcher { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
  }

  func start() throws {
    try eventWatcher?.start()
    codexWatcher?.start(
      urls: [codexPaths.dataRoot, codexPaths.sessionsDirectory, codexPaths.sessionIndexURL]
    )
    requestRefresh()
  }

  func stop() {
    eventWatcher?.stop()
    codexWatcher?.stop()
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
        let watchedURLs = await self.codexProvider.watchedURLs()
        self.codexWatcher?.update(urls: watchedURLs)
        let connectedProviderCount = Set(report.tasks.map(\.identity.provider)).count
        self.statusMenuController.update(
          representative: report.representative,
          connectedProviderCount: connectedProviderCount
        )
      }
      self.refreshInProgress = false
    }
  }
}
