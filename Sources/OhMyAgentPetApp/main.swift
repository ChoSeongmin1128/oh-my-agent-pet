import AgentPetUI
import AppKit

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusMenuController: StatusMenuController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusMenuController = StatusMenuController()
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
