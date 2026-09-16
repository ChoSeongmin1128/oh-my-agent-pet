import AgentPetUI
import AppKit
import Foundation

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusMenuController: StatusMenuController?
  private var taskController: ApplicationTaskController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusMenuController = StatusMenuController()
    self.statusMenuController = statusMenuController

    let environment = ProcessInfo.processInfo.environment
    let homeDirectory =
      environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    do {
      let taskController = try ApplicationTaskController(
        statusMenuController: statusMenuController,
        homeDirectory: homeDirectory,
        environment: environment
      )
      try taskController.start()
      self.taskController = taskController
    } catch {
      statusMenuController.update(representative: nil)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
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
