import AgentPetCore
import AgentPetSprites
import AppKit

@MainActor
final class OverlayContainerView: NSView {
  let petView = PetView(frame: NSRect(origin: .zero, size: DesignTokens.petSize))
  let disclosureButton = NSButton(title: "", target: nil, action: nil)
  let cardDepthHintView = CardDepthHintView(frame: .zero)
  private let scrollView = NSScrollView()
  private let taskListView = TaskListDocumentView()
  private(set) var preferredSize = DesignTokens.petSize
  private(set) var isPetHidden = false
  private(set) var layoutMode: OverlayLayout = .defaultValue
  private var animationsActive = true
  private var geometry = OverlayGeometry.resolve(
    OverlayGeometryInput(
      layout: .defaultValue,
      isPetHidden: false,
      hasCards: false,
      cardsHeight: 0,
      depthLayerCount: 0,
      showsDisclosure: false
    ),
    metrics: .designTokens
  )
  private var toggleExpansion: (() -> Void)?

  var isEmpty: Bool { isPetHidden && scrollView.isHidden }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = taskListView
    disclosureButton.isBordered = false
    disclosureButton.imagePosition = .imageOnly
    disclosureButton.contentTintColor = DesignTokens.textMuted
    disclosureButton.target = self
    disclosureButton.action = #selector(disclosureClicked)
    disclosureButton.isHidden = true
    addSubview(petView)
    addSubview(cardDepthHintView)
    addSubview(scrollView)
    addSubview(disclosureButton)
  }

  required init?(coder: NSCoder) { nil }

  func setSpritePackage(_ package: PetSpritePackage?) {
    petView.setSpritePackage(package)
  }

  func setAnimationsActive(_ isActive: Bool) {
    animationsActive = isActive
    petView.setAnimationsActive(isActive && !isPetHidden)
  }

  // `none` hides only the pet. Cards keep their size, position and drag behavior.
  func setPetHidden(_ hidden: Bool) {
    guard isPetHidden != hidden else { return }
    isPetHidden = hidden
    petView.isHidden = hidden
    petView.setAnimationsActive(animationsActive && !hidden)
    needsLayout = true
  }

  func update(
    presentation: OverlayPresentation,
    layout: OverlayLayout = .defaultValue,
    isCardDepthHintEnabled: Bool = OverlayPreferences.defaultCardDepthHintEnabled,
    onOpen: @escaping (AgentTaskSnapshot) -> Void,
    onPetClick: @escaping () -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    layoutMode = layout
    petView.update(with: presentation)
    petView.onClick = presentation.canToggleExpansion ? onPetClick : nil
    petView.onDragEnded = onDragEnded
    toggleExpansion = onPetClick
    taskListView.update(cards: presentation.cards, onOpen: onOpen, onDragEnded: onDragEnded)
    let cardsHeight = min(
      taskListView.contentHeight,
      CGFloat(DesignTokens.maximumVisibleCards) * DesignTokens.cardHeight
        + CGFloat(DesignTokens.maximumVisibleCards - 1) * DesignTokens.spaceS
    )
    scrollView.hasVerticalScroller = taskListView.contentHeight > cardsHeight
    scrollView.isHidden = presentation.cards.isEmpty
    let cardDepthLayerCount =
      isCardDepthHintEnabled && !presentation.isTemporarilyExpanded
      ? min(presentation.cardDepthLayerCount, CardDepthHintPolicy.maximumLayers) : 0
    cardDepthHintView.setLayerCount(cardDepthLayerCount)
    let showsDisclosure =
      isPetHidden && presentation.canToggleExpansion && !presentation.cards.isEmpty
    disclosureButton.isHidden = !showsDisclosure
    disclosureButton.image = NSImage(
      systemSymbolName: presentation.isTemporarilyExpanded ? "chevron.up" : "chevron.down",
      accessibilityDescription: nil
    )
    disclosureButton.setAccessibilityLabel(
      presentation.isTemporarilyExpanded ? "Show fewer agent tasks" : "Show all agent tasks")
    geometry = OverlayGeometry.resolve(
      OverlayGeometryInput(
        layout: layout,
        isPetHidden: isPetHidden,
        hasCards: !presentation.cards.isEmpty,
        cardsHeight: cardsHeight,
        depthLayerCount: cardDepthLayerCount,
        showsDisclosure: showsDisclosure
      ),
      metrics: .designTokens
    )
    preferredSize = geometry.preferredSize
    frame.size = preferredSize
    needsLayout = true
  }

  override func layout() {
    super.layout()
    petView.frame = geometry.petFrame
    guard !scrollView.isHidden else { return }
    cardDepthHintView.frame = geometry.depthHintFrame
    scrollView.frame = geometry.cardsFrame
    taskListView.frame.size.width = DesignTokens.cardWidth
    if !disclosureButton.isHidden {
      disclosureButton.frame = geometry.disclosureFrame
    }
  }

  @objc private func disclosureClicked() {
    toggleExpansion?()
  }
}
