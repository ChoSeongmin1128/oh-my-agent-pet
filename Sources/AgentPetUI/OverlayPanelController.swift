import AgentPetCore
import AgentPetSprites
import AppKit

public struct OverlayMenuState: Equatable, Sendable {
  public let isVisible: Bool
  public let cardMode: CardDisplayMode
  public let layout: OverlayLayout
  public let isCardDepthHintEnabled: Bool

  public init(
    isVisible: Bool,
    cardMode: CardDisplayMode,
    layout: OverlayLayout = .defaultValue,
    isCardDepthHintEnabled: Bool = OverlayPreferences.defaultCardDepthHintEnabled
  ) {
    self.isVisible = isVisible
    self.cardMode = cardMode
    self.layout = layout
    self.isCardDepthHintEnabled = isCardDepthHintEnabled
  }
}

public enum OverlayControlAction: Equatable, Sendable {
  case toggleVisibility
  case setCardMode(CardDisplayMode)
  case setLayout(OverlayLayout)
  case setCardDepthHintEnabled(Bool)
  case resetPosition
}

enum OverlayPositionGeometry {
  static func anchorOrigin(
    panelOrigin: NSPoint,
    petFrame: NSRect,
    isPetHidden: Bool
  ) -> NSPoint {
    guard !isPetHidden else { return panelOrigin }
    return NSPoint(
      x: panelOrigin.x + petFrame.minX,
      y: panelOrigin.y + petFrame.minY
    )
  }

  static func panelOrigin(
    anchorOrigin: NSPoint,
    petFrame: NSRect,
    isPetHidden: Bool
  ) -> NSPoint {
    guard !isPetHidden else { return anchorOrigin }
    return NSPoint(
      x: anchorOrigin.x - petFrame.minX,
      y: anchorOrigin.y - petFrame.minY
    )
  }
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
    let panelOrigin = panel.frame.origin
    contentView.setPetHidden(hidden)
    render(preservedPanelOrigin: panelOrigin)
    preferencesStore.save(preferences)
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
    case .setLayout(let layout):
      preferences.layout = layout
      render()
    case .setCardDepthHintEnabled(let isEnabled):
      preferences.isCardDepthHintEnabled = isEnabled
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

  private func render(preservedPanelOrigin: NSPoint? = nil) {
    let anchorOrigin = hasRestoredPosition ? currentAnchorOrigin() : nil
    let presentation = presenter.makePresentation(
      tasks: tasks,
      representative: representative,
      savedMode: preferences.cardMode,
      isTemporarilyExpanded: isTemporarilyExpanded
    )
    contentView.update(
      presentation: presentation,
      layout: preferences.layout,
      isCardDepthHintEnabled: preferences.isCardDepthHintEnabled,
      onOpen: { [weak self] task in self?.openTaskHandler?(task) },
      onPetClick: { [weak self] in self?.toggleTemporaryExpansion() },
      onDragEnded: { [weak self] in self?.finishDragging() }
    )
    panel.setContentSize(
      NSSize(
        width: max(contentView.preferredSize.width, 1),
        height: max(contentView.preferredSize.height, 1)))
    contentView.layoutSubtreeIfNeeded()
    if let preservedPanelOrigin {
      panel.setFrameOrigin(preservedPanelOrigin)
    } else if let anchorOrigin {
      panel.setFrameOrigin(
        OverlayPositionGeometry.panelOrigin(
          anchorOrigin: anchorOrigin,
          petFrame: contentView.petView.frame,
          isPetHidden: contentView.isPetHidden
        ))
    }
    clampToVisibleScreen()
    if hasRestoredPosition {
      let adjustedAnchorOrigin = currentAnchorOrigin()
      synchronizePositionPreference(anchorOrigin: adjustedAnchorOrigin)
      if let anchorOrigin, adjustedAnchorOrigin != anchorOrigin {
        preferencesStore.save(preferences)
      }
    }
    applyVisibility()
  }

  private func toggleTemporaryExpansion() {
    guard tasks.count > 1, preferences.cardMode != .many else { return }
    isTemporarilyExpanded.toggle()
    render()
  }

  private func finishDragging() {
    clampToVisibleScreen()
    synchronizePositionPreference(anchorOrigin: currentAnchorOrigin())
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
      panel.setFrameOrigin(
        OverlayPositionGeometry.panelOrigin(
          anchorOrigin: NSPoint(x: position.x, y: position.y),
          petFrame: contentView.petView.frame,
          isPetHidden: contentView.isPetHidden
        ))
      clampToVisibleScreen()
      let adjustedAnchorOrigin = currentAnchorOrigin()
      synchronizePositionPreference(anchorOrigin: adjustedAnchorOrigin)
      if adjustedAnchorOrigin.x != position.x || adjustedAnchorOrigin.y != position.y {
        preferencesStore.save(preferences)
      }
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
    synchronizePositionPreference(anchorOrigin: currentAnchorOrigin())
  }

  private func currentAnchorOrigin() -> NSPoint {
    OverlayPositionGeometry.anchorOrigin(
      panelOrigin: panel.frame.origin,
      petFrame: contentView.petView.frame,
      isPetHidden: contentView.isPetHidden
    )
  }

  private func synchronizePositionPreference(anchorOrigin: NSPoint) {
    preferences.position = OverlayPosition(x: anchorOrigin.x, y: anchorOrigin.y)
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
      OverlayMenuState(
        isVisible: preferences.isVisible,
        cardMode: preferences.cardMode,
        layout: preferences.layout,
        isCardDepthHintEnabled: preferences.isCardDepthHintEnabled
      )
    )
  }
}

@MainActor
private final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
