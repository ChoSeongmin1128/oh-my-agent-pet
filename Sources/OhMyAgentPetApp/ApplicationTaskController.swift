import AgentPetCore
import AgentPetEvents
import AgentPetNavigation
import AgentPetProviders
import AgentPetUI
import Foundation

@MainActor
final class ApplicationTaskController {
  private let statusMenuController: StatusMenuController
  private let overlayController: OverlayPanelController
  private let coordinator: ProviderCoordinator
  private let connectionCoordinator: ProviderConnectionCoordinator
  private let providerAdapters: [any TaskProviderAdapter]
  private let connectionInspectors: [any ProviderConnectionInspecting]
  private let navigator: TaskNavigator
  private let runtimeHealth: ApplicationRuntimeHealth
  private var eventWatcher: AgentEventLogWatcher?
  private var providerFileWatcher: AgentFileSetWatcher?
  private var connectionFileWatcher: AgentFileSetWatcher?
  private var refreshInProgress = false
  private var refreshPending = false
  private var connectionRefreshPending = true
  private var activeTaskProviders = Set<ProviderIdentifier>()

  init(
    statusMenuController: StatusMenuController,
    overlayController: OverlayPanelController,
    homeDirectory: URL,
    environment: [String: String],
    cliExecutableURL: URL,
    runtimeHealth: ApplicationRuntimeHealth
  ) throws {
    self.statusMenuController = statusMenuController
    self.overlayController = overlayController
    self.runtimeHealth = runtimeHealth
    navigator = TaskNavigator()
    let runtimes = ApplicationProviderCatalog.runtimes(
      homeDirectory: homeDirectory,
      environment: environment,
      cliExecutableURL: cliExecutableURL
    )
    providerAdapters = runtimes.map(\.adapter)
    connectionInspectors = runtimes.map(\.connectionInspector)
    coordinator = try ProviderCoordinator(adapters: providerAdapters)
    connectionCoordinator = try ProviderConnectionCoordinator(
      inspectors: connectionInspectors
    )
    eventWatcher = AgentEventLogWatcher(
      eventsURL: ApplicationPaths(homeDirectory: homeDirectory).eventsURL
    ) { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
    providerFileWatcher = AgentFileSetWatcher { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
    connectionFileWatcher = AgentFileSetWatcher { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.connectionRefreshPending = true
        self.requestRefresh()
      }
    }
    statusMenuController.setOpenTaskHandler { [weak self] task in
      self?.open(task)
    }
    statusMenuController.setOverlayControlHandler { [weak overlayController] action in
      overlayController?.handle(action)
    }
    overlayController.setOpenTaskHandler { [weak self] task in
      self?.open(task)
    }
  }

  func start() throws {
    try eventWatcher?.start()
    providerFileWatcher?.start(urls: [])
    connectionFileWatcher?.start(urls: connectionWatchedURLs())
    requestRefresh()
  }

  func stop() {
    eventWatcher?.stop()
    providerFileWatcher?.stop()
    connectionFileWatcher?.stop()
    overlayController.stop()
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
        self.runtimeHealth.updateProviderFailures(report.failures)
        let currentTaskProviders = Set(report.tasks.map(\.identity.provider))
        let newlyActiveProviders = currentTaskProviders.subtracting(self.activeTaskProviders)
        self.activeTaskProviders = currentTaskProviders
        let shouldRefreshConnections =
          self.connectionRefreshPending
          || newlyActiveProviders.contains(where: {
            self.runtimeHealth.providerConnections[$0]?.state != .connected
          })
        var watchedURLs = Set<URL>()
        for adapter in self.providerAdapters {
          for url in await adapter.watchedURLs() {
            watchedURLs.insert(url)
          }
        }
        self.providerFileWatcher?.update(urls: watchedURLs.sorted { $0.path < $1.path })
        self.publish(report)
        if shouldRefreshConnections {
          self.connectionRefreshPending = false
          let statuses = await self.connectionCoordinator.refresh()
          self.runtimeHealth.updateConnections(statuses)
          self.connectionFileWatcher?.update(urls: self.connectionWatchedURLs())
          self.publish(report)
        }
      }
      self.refreshInProgress = false
    }
  }

  private func publish(_ report: ProviderRefreshReport) {
    let connectedProviderCount = runtimeHealth.connectedProviderCount
    statusMenuController.update(
      representative: report.representative,
      connectedProviderCount: connectedProviderCount
    )
    overlayController.update(
      tasks: report.tasks,
      representative: report.representative,
      connectedProviderCount: connectedProviderCount
    )
  }

  private func connectionWatchedURLs() -> [URL] {
    Array(Set(connectionInspectors.flatMap { $0.watchedURLs() }))
      .sorted { $0.path < $1.path }
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
