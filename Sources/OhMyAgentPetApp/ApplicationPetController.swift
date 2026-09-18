import AgentPetEvents
import AgentPetLibrary
import AgentPetUI
import Foundation

// Applies the saved pet selection to the overlay and follows library changes made by the
// settings window or the `omapet pet` CLI through the shared selection file.
@MainActor
final class ApplicationPetController {
  private let service: PetLibraryService
  private let overlayController: OverlayPanelController
  private let settingsModel: SettingsModel
  private let runtimeHealth: ApplicationRuntimeHealth
  private var watcher: AgentFileSetWatcher?
  private var refreshInProgress = false
  private var refreshPending = false

  init(
    service: PetLibraryService,
    overlayController: OverlayPanelController,
    settingsModel: SettingsModel,
    runtimeHealth: ApplicationRuntimeHealth
  ) {
    self.service = service
    self.overlayController = overlayController
    self.settingsModel = settingsModel
    self.runtimeHealth = runtimeHealth
  }

  func start() {
    do {
      try service.prepare()
    } catch {
      runtimeHealth.recordPetLibraryPrepareFailure()
    }
    watcher = AgentFileSetWatcher { [weak self] in
      Task { @MainActor [weak self] in
        self?.requestRefresh()
      }
    }
    watcher?.start(urls: watchedURLs)
    requestRefresh()
  }

  func stop() {
    watcher?.stop()
  }

  func requestRefresh() {
    refreshPending = true
    guard !refreshInProgress else { return }
    refreshInProgress = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      while self.refreshPending {
        self.refreshPending = false
        let service = self.service
        let resolution = await Task.detached(priority: .userInitiated) {
          service.resolveSelection()
        }.value
        self.overlayController.setPetPackage(resolution.package)
        self.overlayController.setPetHidden(resolution.selection == .none)
        self.watcher?.update(urls: self.watchedURLs)
        await self.settingsModel.petLibrary.refresh()
      }
      self.refreshInProgress = false
    }
  }

  private var watchedURLs: [URL] {
    [
      service.paths.rootDirectory,
      service.paths.libraryDirectory,
      service.paths.selectionURL,
    ]
  }
}
