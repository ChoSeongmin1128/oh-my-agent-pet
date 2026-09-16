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

    let prefix = TaskVisualStatus.resolve(representative.task).label
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
  private let overlayVisibilityItem = NSMenuItem(
    title: "Show Pet & Cards",
    action: #selector(toggleOverlayVisibility),
    keyEquivalent: ""
  )
  private let oneCardItem = NSMenuItem(
    title: "One Card",
    action: #selector(selectOneCard),
    keyEquivalent: ""
  )
  private let manyCardsItem = NSMenuItem(
    title: "All Cards",
    action: #selector(selectManyCards),
    keyEquivalent: ""
  )
  private let noCardsItem = NSMenuItem(
    title: "No Cards",
    action: #selector(selectNoCards),
    keyEquivalent: ""
  )
  private var currentTask: AgentTaskSnapshot?
  private var openTaskHandler: ((AgentTaskSnapshot) -> Void)?
  private var overlayControlHandler: ((OverlayControlAction) -> Void)?

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

  public func setOverlayControlHandler(_ handler: @escaping (OverlayControlAction) -> Void) {
    overlayControlHandler = handler
  }

  public func updateOverlayState(_ state: OverlayMenuState) {
    overlayVisibilityItem.state = state.isVisible ? .on : .off
    oneCardItem.state = state.cardMode == .one ? .on : .off
    manyCardsItem.state = state.cardMode == .many ? .on : .off
    noCardsItem.state = state.cardMode == .none ? .on : .off
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
    overlayVisibilityItem.target = self
    oneCardItem.target = self
    manyCardsItem.target = self
    noCardsItem.target = self

    let cardModeItem = NSMenuItem(title: "Cards", action: nil, keyEquivalent: "")
    let cardModeMenu = NSMenu(title: "Cards")
    cardModeMenu.addItem(oneCardItem)
    cardModeMenu.addItem(manyCardsItem)
    cardModeMenu.addItem(noCardsItem)
    cardModeItem.submenu = cardModeMenu

    let resetPosition = NSMenuItem(
      title: "Reset Pet Position",
      action: #selector(resetOverlayPosition),
      keyEquivalent: ""
    )
    resetPosition.target = self

    let quit = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
    quit.target = self

    menu.addItem(title)
    menu.addItem(statusRow)
    menu.addItem(navigationFeedbackRow)
    menu.addItem(.separator())
    menu.addItem(overlayVisibilityItem)
    menu.addItem(cardModeItem)
    menu.addItem(resetPosition)
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

  @objc private func toggleOverlayVisibility() {
    overlayControlHandler?(.toggleVisibility)
  }

  @objc private func selectOneCard() {
    overlayControlHandler?(.setCardMode(.one))
  }

  @objc private func selectManyCards() {
    overlayControlHandler?(.setCardMode(.many))
  }

  @objc private func selectNoCards() {
    overlayControlHandler?(.setCardMode(.none))
  }

  @objc private func resetOverlayPosition() {
    overlayControlHandler?(.resetPosition)
  }
}
