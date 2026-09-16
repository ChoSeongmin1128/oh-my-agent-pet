import AgentPetClaude
import AgentPetCodex
import AgentPetCore
import AgentPetEvents
import AgentPetNavigation
import AgentPetProviders
import AgentPetUI
import Foundation

@MainActor
final class ApplicationTaskController {
  private let statusMenuController: StatusMenuController
  private let coordinator: ProviderCoordinator
  private let codexProvider: CodexTaskProvider
  private let codexPaths: CodexPaths
  private let navigator: TaskNavigator
  private let claudeDesktopSessionsDirectory: URL
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
    claudeDesktopSessionsDirectory = claudePaths.desktopSessionsDirectory
    navigator = TaskNavigator()
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
    statusMenuController.setOpenTaskHandler { [weak self] task in
      self?.open(task)
    }
  }

  func start() throws {
    try eventWatcher?.start()
    codexWatcher?.start(
      urls: [
        codexPaths.dataRoot,
        codexPaths.sessionsDirectory,
        codexPaths.sessionIndexURL,
        claudeDesktopSessionsDirectory.deletingLastPathComponent(),
        claudeDesktopSessionsDirectory,
      ]
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
        var watchedURLs = await self.codexProvider.watchedURLs()
        watchedURLs.append(self.claudeDesktopSessionsDirectory.deletingLastPathComponent())
        watchedURLs.append(self.claudeDesktopSessionsDirectory)
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

  private func open(_ task: AgentTaskSnapshot) {
    switch navigator.navigate(to: task) {
    case .exact:
      statusMenuController.showNavigationFeedback(nil)
    case .appOnly:
      statusMenuController.showNavigationFeedback("App opened; task was not selected")
    case .failed:
      statusMenuController.showNavigationFeedback("Task is no longer available")
    }
  }
}
