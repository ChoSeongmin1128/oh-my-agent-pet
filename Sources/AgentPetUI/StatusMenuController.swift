import AgentPetCore
import AppKit

public enum StatusMenuPresentation {
  public static func title(for representative: RepresentativeTask?) -> String {
    guard let representative else {
      return "No connected tasks"
    }

    if representative.reason == .intervention {
      return "Input needed · \(representative.task.title)"
    }

    let prefix: String
    switch representative.task.result {
    case .failed:
      prefix = "Failed"
    case .completed where representative.task.hasUnseenCompletion:
      prefix = "Finished"
    default:
      prefix = representative.task.work == .running ? "Working" : "Ready"
    }
    return "\(prefix) · \(representative.task.title)"
  }
}

@MainActor
public final class StatusMenuController: NSObject {
  private let statusItem: NSStatusItem
  private let statusRow = NSMenuItem(title: "No connected tasks", action: nil, keyEquivalent: "")

  public override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()
    configureButton()
    configureMenu()
  }

  public func update(representative: RepresentativeTask?) {
    statusRow.title = StatusMenuPresentation.title(for: representative)
  }

  private func configureButton() {
    guard let button = statusItem.button else {
      return
    }
    button.image = NSImage(
      systemSymbolName: "pawprint.fill", accessibilityDescription: "Oh My Agent Pet")
    button.toolTip = "Oh My Agent Pet"
  }

  private func configureMenu() {
    let menu = NSMenu()
    let title = NSMenuItem(title: "Oh My Agent Pet", action: nil, keyEquivalent: "")
    title.isEnabled = false
    statusRow.isEnabled = false

    let quit = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
    quit.target = self

    menu.addItem(title)
    menu.addItem(statusRow)
    menu.addItem(.separator())
    menu.addItem(quit)
    statusItem.menu = menu
  }

  @objc private func quitApplication() {
    NSApplication.shared.terminate(nil)
  }
}
