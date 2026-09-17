import AgentPetCore
import AgentPetSprites
import AppKit

public struct OverlayMenuState: Equatable, Sendable {
  public let isVisible: Bool
  public let cardMode: CardDisplayMode

  public init(isVisible: Bool, cardMode: CardDisplayMode) {
    self.isVisible = isVisible
    self.cardMode = cardMode
  }
}

public enum OverlayControlAction: Equatable, Sendable {
  case toggleVisibility
  case setCardMode(CardDisplayMode)
  case resetPosition
}

@MainActor
public final class OverlayPanelController {
  private let panel: OverlayPanel
  private let contentView: OverlayContainerView
  private let preferencesStore: OverlayPreferencesStore
  private let presenter = OverlayPresenter()
  private var preferences: OverlayPreferences
  private var tasks: [AgentTaskSnapshot] = []
  private var representative: RepresentativeTask?
  private var isTemporarilyExpanded = false
  private var hasRestoredPosition = false
  private var openTaskHandler: ((AgentTaskSnapshot) -> Void)?
  private var stateHandler: ((OverlayMenuState) -> Void)?

  public init(preferencesStore: OverlayPreferencesStore = OverlayPreferencesStore()) {
    self.preferencesStore = preferencesStore
    preferences = preferencesStore.load()
    panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: DesignTokens.petSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    contentView = OverlayContainerView(frame: NSRect(origin: .zero, size: DesignTokens.petSize))
    panel.contentView = contentView
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.hidesOnDeactivate = false
    render()
    restorePosition()
    hasRestoredPosition = true
    applyVisibility()
  }

  public func setOpenTaskHandler(_ handler: @escaping (AgentTaskSnapshot) -> Void) {
    openTaskHandler = handler
  }

  public func setStateHandler(_ handler: @escaping (OverlayMenuState) -> Void) {
    stateHandler = handler
    publishState()
  }

  public func setPetPackage(_ package: PetSpritePackage?) {
    contentView.setSpritePackage(package)
  }

  public func setPetHidden(_ hidden: Bool) {
    guard contentView.isPetHidden != hidden else { return }
    contentView.setPetHidden(hidden)
    render()
  }

  public func update(tasks: [AgentTaskSnapshot], representative: RepresentativeTask?) {
    self.tasks = tasks
    self.representative = representative
    if tasks.count <= 1 { isTemporarilyExpanded = false }
    render()
  }

  public func handle(_ action: OverlayControlAction) {
    switch action {
    case .toggleVisibility:
      preferences.isVisible.toggle()
      applyVisibility()
    case .setCardMode(let mode):
      preferences.cardMode = mode
      isTemporarilyExpanded = false
      render()
    case .resetPosition:
      preferences.position = nil
      positionAtDefaultLocation()
    }
    preferencesStore.save(preferences)
    publishState()
  }

  public func stop() {
    contentView.setAnimationsActive(false)
    panel.orderOut(nil)
  }

  private func render() {
    let presentation = presenter.makePresentation(
      tasks: tasks,
      representative: representative,
      savedMode: preferences.cardMode,
      isTemporarilyExpanded: isTemporarilyExpanded
    )
    contentView.update(
      presentation: presentation,
      onOpen: { [weak self] task in self?.openTaskHandler?(task) },
      onPetClick: { [weak self] in self?.toggleTemporaryExpansion() },
      onDragEnded: { [weak self] in self?.finishDragging() }
    )
    let origin = panel.frame.origin
    panel.setContentSize(
      NSSize(
        width: max(contentView.preferredSize.width, 1),
        height: max(contentView.preferredSize.height, 1)))
    panel.setFrameOrigin(origin)
    clampToVisibleScreen()
    applyVisibility()
  }

  private func toggleTemporaryExpansion() {
    guard tasks.count > 1, preferences.cardMode != .many else { return }
    isTemporarilyExpanded.toggle()
    render()
  }

  private func finishDragging() {
    clampToVisibleScreen()
    preferences.position = OverlayPosition(
      x: panel.frame.origin.x,
      y: panel.frame.origin.y
    )
    preferencesStore.save(preferences)
  }

  // The panel is shown only after the saved position is restored, and ordering calls happen
  // only on an actual visibility change so task refreshes do not re-order the panel.
  private func applyVisibility() {
    contentView.setAnimationsActive(preferences.isVisible)
    guard hasRestoredPosition else { return }
    let shouldShow = preferences.isVisible && !contentView.isEmpty
    if shouldShow, !panel.isVisible {
      panel.orderFrontRegardless()
    } else if !shouldShow, panel.isVisible {
      panel.orderOut(nil)
    }
  }

  private func restorePosition() {
    if let position = preferences.position {
      panel.setFrameOrigin(NSPoint(x: position.x, y: position.y))
      clampToVisibleScreen()
    } else {
      positionAtDefaultLocation()
    }
  }

  private func positionAtDefaultLocation() {
    guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
    panel.setFrameOrigin(
      NSPoint(
        x: visibleFrame.maxX - panel.frame.width - DesignTokens.screenMargin,
        y: visibleFrame.minY + DesignTokens.screenMargin
      )
    )
    preferences.position = OverlayPosition(x: panel.frame.minX, y: panel.frame.minY)
  }

  private func clampToVisibleScreen() {
    guard let visibleFrame = targetScreen()?.visibleFrame else { return }
    let margin = DesignTokens.screenMargin
    let x = min(
      max(panel.frame.minX, visibleFrame.minX + margin),
      max(visibleFrame.minX + margin, visibleFrame.maxX - panel.frame.width - margin)
    )
    let y = min(
      max(panel.frame.minY, visibleFrame.minY + margin),
      max(visibleFrame.minY + margin, visibleFrame.maxY - panel.frame.height - margin)
    )
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  private func targetScreen() -> NSScreen? {
    panel.screen
      ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
      ?? NSScreen.main
  }

  private func publishState() {
    stateHandler?(
      OverlayMenuState(isVisible: preferences.isVisible, cardMode: preferences.cardMode)
    )
  }
}

@MainActor
private final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
