import AgentPetCore
import AppKit

public enum StatusMenuPresentation {
  public static func title(
    for representative: RepresentativeTask?,
    connectedProviderCount: Int = 1
  ) -> String {
    guard let representative else {
      return "No connected tasks"
    }

    let prefix: String
    if representative.reason == .intervention {
      prefix = "Input needed"
    } else {
      switch representative.task.result {
      case .failed:
        prefix = "Failed"
      case .interrupted:
        prefix = "Stopped"
      case .completed where representative.task.hasUnseenCompletion:
        prefix = "Finished"
      default:
        prefix = representative.task.work == .running ? "Working" : "Ready"
      }
    }
    var parts = [prefix, representative.task.title]
    if connectedProviderCount > 1 {
      parts.append(providerLabel(representative.task.identity.provider))
    }
    return parts.joined(separator: " · ")
  }

  private static func providerLabel(_ provider: ProviderIdentifier) -> String {
    switch provider.rawValue {
    case "claude": "Claude"
    case "codex": "Codex"
    default: provider.rawValue
    }
  }
}

@MainActor
public final class StatusMenuController: NSObject {
  private let statusItem: NSStatusItem
  private let statusRow = NSMenuItem(
    title: "No connected tasks",
    action: #selector(openCurrentTask),
    keyEquivalent: ""
  )
  private let navigationFeedbackRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private var currentTask: AgentTaskSnapshot?
  private var openTaskHandler: ((AgentTaskSnapshot) -> Void)?

  public override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()
    configureButton()
    configureMenu()
  }

  public func update(
    representative: RepresentativeTask?,
    connectedProviderCount: Int = 1
  ) {
    let previousTaskKey = currentTask?.identity.stableKey
    statusRow.title = StatusMenuPresentation.title(
      for: representative,
      connectedProviderCount: connectedProviderCount
    )
    currentTask = representative?.task
    statusRow.isEnabled = representative?.task.navigationTarget != nil
    if representative?.task.identity.stableKey != previousTaskKey {
      showNavigationFeedback(nil)
    }
  }

  public func setOpenTaskHandler(_ handler: @escaping (AgentTaskSnapshot) -> Void) {
    openTaskHandler = handler
  }

  public func showNavigationFeedback(_ message: String?) {
    navigationFeedbackRow.title = message ?? ""
    navigationFeedbackRow.isHidden = message == nil
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
    statusRow.target = self
    navigationFeedbackRow.isEnabled = false
    navigationFeedbackRow.isHidden = true

    let quit = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
    quit.target = self

    menu.addItem(title)
    menu.addItem(statusRow)
    menu.addItem(navigationFeedbackRow)
    menu.addItem(.separator())
    menu.addItem(quit)
    statusItem.menu = menu
  }

  @objc private func quitApplication() {
    NSApplication.shared.terminate(nil)
  }

  @objc private func openCurrentTask() {
    guard let currentTask else { return }
    openTaskHandler?(currentTask)
  }
}
