import AgentPetClaude
import AgentPetCore
import AgentPetLibrary
import AgentPetUI
import AppKit
import Foundation

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusMenuController: StatusMenuController?
  private var overlayController: OverlayPanelController?
  private var taskController: ApplicationTaskController?
  private var petController: ApplicationPetController?
  private var settingsWindowController: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusMenuController = StatusMenuController()
    let overlayController = OverlayPanelController()
    self.statusMenuController = statusMenuController
    self.overlayController = overlayController

    let environment = ProcessInfo.processInfo.environment
    let homeDirectory =
      environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    let applicationSupportDirectory =
      ApplicationPaths(homeDirectory: homeDirectory).applicationSupportDirectory
    let libraryService = PetLibraryService(
      paths: PetLibraryPaths(applicationSupportDirectory: applicationSupportDirectory))

    var petController: ApplicationPetController?
    let petLibraryModel = PetLibraryViewModel(service: libraryService) {
      petController?.requestRefresh()
    }
    let settingsModel = SettingsModel(petLibrary: petLibraryModel)
    let runtimeHealth = ApplicationRuntimeHealth()
    let settingsWindowController = SettingsWindowController(model: settingsModel)
    self.settingsWindowController = settingsWindowController
    petController = ApplicationPetController(
      service: libraryService,
      overlayController: overlayController,
      settingsModel: settingsModel,
      runtimeHealth: runtimeHealth
    )
    self.petController = petController

    settingsModel.setOverlayActionHandler { [weak overlayController] action in
      overlayController?.handle(action)
    }
    overlayController.setStateHandler { [weak statusMenuController, weak settingsModel] state in
      statusMenuController?.updateOverlayState(state)
      settingsModel?.updateOverlayState(state)
    }
    statusMenuController.setSettingsHandler { [weak settingsWindowController] in
      settingsWindowController?.show()
    }
    NSApp.mainMenu = ApplicationMainMenu.make(
      settingsTarget: self, settingsAction: #selector(openSettings))

    do {
      let taskController = try ApplicationTaskController(
        statusMenuController: statusMenuController,
        overlayController: overlayController,
        homeDirectory: homeDirectory,
        environment: environment,
        cliExecutableURL: ApplicationPaths.companionCLIURL(
          appExecutableURL: Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        ),
        runtimeHealth: runtimeHealth
      )
      try taskController.start()
      self.taskController = taskController
    } catch {
      runtimeHealth.recordTaskControllerStartFailure()
      statusMenuController.update(representative: nil)
    }
    petController?.start()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    settingsWindowController?.show()
    return false
  }

  @objc private func openSettings() {
    settingsWindowController?.show()
  }

  func applicationWillTerminate(_ notification: Notification) {
    petController?.stop()
    taskController?.stop()
  }
}

@main
@MainActor
private enum OhMyAgentPetMain {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
  }
}
