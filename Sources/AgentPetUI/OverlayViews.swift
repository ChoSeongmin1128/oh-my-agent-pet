import AgentPetCore
import AgentPetSprites
import AppKit

private final class GazeRefreshGate: @unchecked Sendable {
  private let lock = NSLock()
  private var isPending = false

  func begin() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !isPending else { return false }
    isPending = true
    return true
  }

  func end() {
    lock.lock()
    isPending = false
    lock.unlock()
  }
}

@MainActor
class OverlayInteractionView: NSView {
  var onClick: (() -> Void)?
  var onDragEnded: (() -> Void)?

  private var mouseDownLocation: NSPoint?
  private var windowOriginAtMouseDown: NSPoint?
  private var mouseDownTime: TimeInterval?
  private var maximumDistance: CGFloat = 0

  override var isOpaque: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = NSEvent.mouseLocation
    windowOriginAtMouseDown = window?.frame.origin
    mouseDownTime = event.timestamp
    maximumDistance = 0
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = mouseDownLocation, let origin = windowOriginAtMouseDown else { return }
    let current = NSEvent.mouseLocation
    let delta = NSPoint(x: current.x - start.x, y: current.y - start.y)
    maximumDistance = max(maximumDistance, hypot(delta.x, delta.y))
    guard maximumDistance >= DesignTokens.dragActivationDistance else { return }
    window?.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
  }

  override func mouseUp(with event: NSEvent) {
    guard let startTime = mouseDownTime else { return }
    let intent = OverlayPointerIntentResolver(
      dragDistance: DesignTokens.dragActivationDistance,
      holdDuration: DesignTokens.longPressDuration
    ).resolve(distance: maximumDistance, duration: max(0, event.timestamp - startTime))
    mouseDownLocation = nil
    windowOriginAtMouseDown = nil
    mouseDownTime = nil
    maximumDistance = 0
    switch intent {
    case .click:
      onClick?()
    case .drag:
      onDragEnded?()
    case .hold:
      break
    }
  }
}

@MainActor
final class PetView: OverlayInteractionView {
  private var status: TaskVisualStatus = .ready
  private var interventionCount = 0
  private var showsCompletionDot = false
  private var canExpand = false
  private var spritePackage: PetSpritePackage?
  private var spriteImages: [Int: NSImage] = [:]
  private var animationState = PetAnimationState.idle
  private var animationTimeline = PetAnimationTimeline(state: .idle, reducedMotion: false)
  private var animationStartedAt = ProcessInfo.processInfo.systemUptime
  private var animationTimer: Timer?
  private var currentAnimationFrame: PetAnimationFrame?
  private var gazePose: PetGazePose?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private let gazeRefreshGate = GazeRefreshGate()
  private var animationsActive = true
  private var isAttachedToWindow = false
  private var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

  // Animation and mouse monitoring run only while the view is both enabled and inside a window,
  // so a discarded settings preview cannot keep timers alive.
  private var isActive: Bool { animationsActive && isAttachedToWindow }
  var isAnimating: Bool { animationTimer != nil }
  var hasMouseMonitors: Bool { globalMouseMonitor != nil || localMouseMonitor != nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(accessibilityDisplayOptionsDidChange),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) { nil }

  func setSpritePackage(_ package: PetSpritePackage?) {
    guard spritePackage !== package else { return }
    spritePackage = package
    spriteImages.removeAll(keepingCapacity: false)
    applyActivity()
  }

  func setAnimationsActive(_ isActive: Bool) {
    guard animationsActive != isActive else { return }
    animationsActive = isActive
    applyActivity()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    let attached = window != nil
    guard attached != isAttachedToWindow else { return }
    isAttachedToWindow = attached
    applyActivity()
  }

  private func applyActivity() {
    if isActive {
      updateGazeMonitoring()
      refreshGaze()
      restartAnimation()
    } else {
      animationTimer?.invalidate()
      animationTimer = nil
      stopGazeMonitoring()
      gazePose = nil
      currentAnimationFrame = nil
      needsDisplay = true
    }
  }

  func update(with presentation: OverlayPresentation) {
    status = presentation.petStatus
    interventionCount = presentation.additionalInterventionCount
    showsCompletionDot = presentation.showsPetCompletionDot
    canExpand = presentation.canToggleExpansion
    setAccessibilityRole(canExpand ? .button : .group)
    setAccessibilityLabel("Oh My Agent Pet, \(status.label)")
    setAccessibilityHelp(canExpand ? "Show or hide all agent tasks" : "Agent task status")
    let nextAnimationState = status.petAnimationState
    if nextAnimationState != animationState {
      animationState = nextAnimationState
      updateGazeMonitoring()
      refreshGaze()
      restartAnimation()
    }
    needsDisplay = true
  }

  override func accessibilityPerformPress() -> Bool {
    guard canExpand else { return false }
    onClick?()
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if drawSprite() {
      VectorPetRenderer.drawStatusMark(in: bounds.insetBy(dx: 8, dy: 8), status: status)
      drawBadge()
      return
    }
    VectorPetRenderer.draw(in: bounds, status: status)
    drawBadge()
  }

  @objc private func accessibilityDisplayOptionsDidChange() {
    let nextValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    guard nextValue != reducedMotion else { return }
    reducedMotion = nextValue
    applyActivity()
  }

  private func restartAnimation() {
    animationTimer?.invalidate()
    animationTimer = nil
    animationTimeline = PetAnimationTimeline(
      state: animationState,
      reducedMotion: reducedMotion
    )
    animationStartedAt = ProcessInfo.processInfo.systemUptime
    refreshAnimationFrame()
  }

  @objc private func refreshAnimationFrame() {
    animationTimer?.invalidate()
    animationTimer = nil
    guard spritePackage != nil, isActive else {
      currentAnimationFrame = nil
      needsDisplay = true
      return
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - animationStartedAt
    guard let sample = animationTimeline.sample(at: elapsed) else { return }
    if currentAnimationFrame != sample.frame {
      currentAnimationFrame = sample.frame
      needsDisplay = true
    }
    guard let remainingDuration = sample.remainingDuration else { return }
    animationTimer = Timer.scheduledTimer(
      timeInterval: max(remainingDuration, 0.01),
      target: self,
      selector: #selector(refreshAnimationFrame),
      userInfo: nil,
      repeats: false
    )
  }

  private func drawSprite() -> Bool {
    guard let spritePackage, let animationFrame = currentAnimationFrame else { return false }
    let row = gazePose?.row ?? animationFrame.row
    let column = gazePose?.column ?? animationFrame.column
    let key = row * PetSpriteVersion.columns + column
    let image: NSImage
    if let cached = spriteImages[key] {
      image = cached
    } else {
      guard let cropped = spritePackage.frame(row: row, column: column) else {
        return false
      }
      image = NSImage(
        cgImage: cropped,
        size: NSSize(
          width: PetSpriteVersion.cellWidth,
          height: PetSpriteVersion.cellHeight
        )
      )
      spriteImages[key] = image
    }
    let scale = min(
      bounds.width / CGFloat(PetSpriteVersion.cellWidth),
      bounds.height / CGFloat(PetSpriteVersion.cellHeight)
    )
    let destination = NSRect(
      x: bounds.midX - CGFloat(PetSpriteVersion.cellWidth) * scale / 2,
      y: bounds.midY - CGFloat(PetSpriteVersion.cellHeight) * scale / 2,
      width: CGFloat(PetSpriteVersion.cellWidth) * scale,
      height: CGFloat(PetSpriteVersion.cellHeight) * scale
    )
    let previousInterpolation = NSGraphicsContext.current?.imageInterpolation
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
      in: destination,
      from: .zero,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: nil
    )
    if let previousInterpolation {
      NSGraphicsContext.current?.imageInterpolation = previousInterpolation
    }
    return true
  }

  private func updateGazeMonitoring() {
    let shouldMonitor =
      isActive
      && !reducedMotion
      && spritePackage?.version.supportsGaze == true
      && [.idle, .running, .waving].contains(animationState)
    if shouldMonitor, globalMouseMonitor == nil, localMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
        [weak self] _ in
        self?.queueGazeRefresh()
      }
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
        [weak self] event in
        self?.queueGazeRefresh()
        return event
      }
    } else if !shouldMonitor {
      stopGazeMonitoring()
      gazePose = nil
    }
  }

  private nonisolated func queueGazeRefresh() {
    let gate = gazeRefreshGate
    guard gate.begin() else { return }
    Task { @MainActor [weak self] in
      defer { gate.end() }
      self?.refreshGaze()
    }
  }

  private func stopGazeMonitoring() {
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
  }

  private func refreshGaze() {
    guard isActive,
      !reducedMotion,
      let spritePackage,
      let window
    else {
      setGazePose(nil)
      return
    }
    let headInView = NSPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.55)
    let headInWindow = convert(headInView, to: nil)
    let headOnScreen = window.convertPoint(toScreen: headInWindow)
    let mouse = NSEvent.mouseLocation
    let pose = PetGazeResolver.pose(
      deltaX: mouse.x - headOnScreen.x,
      deltaY: mouse.y - headOnScreen.y,
      deadZoneRadius: min(bounds.width, bounds.height) * 0.15,
      version: spritePackage.version,
      state: animationState
    )
    setGazePose(pose)
  }

  private func setGazePose(_ pose: PetGazePose?) {
    guard gazePose != pose else { return }
    gazePose = pose
    needsDisplay = true
  }

  private func drawBadge() {
    if interventionCount > 0 {
      let text = interventionCount > 9 ? "9+" : "\(interventionCount)"
      let badgeRect = NSRect(x: bounds.maxX - 24, y: bounds.maxY - 23, width: 21, height: 19)
      DesignTokens.statusWaiting.setFill()
      NSBezierPath(roundedRect: badgeRect, xRadius: 9.5, yRadius: 9.5).fill()
      let attributes: [NSAttributedString.Key: Any] = [
        .font: DesignTokens.metadataFont,
        .foregroundColor: NSColor.black,
      ]
      let size = text.size(withAttributes: attributes)
      text.draw(
        at: NSPoint(x: badgeRect.midX - size.width / 2, y: badgeRect.midY - size.height / 2),
        withAttributes: attributes
      )
    } else if showsCompletionDot {
      DesignTokens.statusCompleted.setFill()
      NSBezierPath(
        ovalIn: NSRect(x: bounds.maxX - 16, y: bounds.maxY - 15, width: 10, height: 10)
      ).fill()
    }
  }
}

@MainActor
final class TaskCardView: OverlayInteractionView {
  let presentation: TaskCardPresentation

  private let titleLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")

  init(
    presentation: TaskCardPresentation,
    onOpen: @escaping (AgentTaskSnapshot) -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    self.presentation = presentation
    super.init(
      frame: NSRect(
        origin: .zero, size: NSSize(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight))
    )
    wantsLayer = true
    titleLabel.stringValue = presentation.task.title
    titleLabel.font = DesignTokens.titleFont
    titleLabel.textColor = DesignTokens.textPrimary
    titleLabel.lineBreakMode = .byTruncatingTail
    statusLabel.stringValue = presentation.status.label
    statusLabel.font = DesignTokens.statusFont
    statusLabel.textColor = statusColor(presentation.status)
    metadataLabel.stringValue = [presentation.providerLabel, presentation.shortTaskID]
      .compactMap { $0 }.joined(separator: " · ")
    metadataLabel.font = DesignTokens.metadataFont
    metadataLabel.textColor = DesignTokens.textMuted
    metadataLabel.alignment = .right
    addSubview(titleLabel)
    addSubview(statusLabel)
    addSubview(metadataLabel)
    self.onClick = presentation.task.navigationTarget == nil ? nil : { onOpen(presentation.task) }
    self.onDragEnded = onDragEnded
    setAccessibilityElement(true)
    setAccessibilityRole(presentation.task.navigationTarget == nil ? .group : .button)
    setAccessibilityLabel("\(presentation.status.label), \(presentation.task.title)")
    setAccessibilityHelp(
      presentation.task.navigationTarget == nil
        ? "This task cannot be opened" : "Open this agent task"
    )
  }

  required init?(coder: NSCoder) { nil }

  override func accessibilityPerformPress() -> Bool {
    guard let onClick else { return false }
    onClick()
    return true
  }

  override func layout() {
    super.layout()
    titleLabel.frame = NSRect(
      x: DesignTokens.cardContentLeading,
      y: bounds.height - DesignTokens.cardVerticalInset - DesignTokens.cardTitleHeight,
      width: bounds.width
        - DesignTokens.cardContentLeading
        - DesignTokens.cardContentTrailing
        - DesignTokens.resultDotSize
        - DesignTokens.spaceM,
      height: DesignTokens.cardTitleHeight
    )
    statusLabel.frame = NSRect(
      x: DesignTokens.cardContentLeading,
      y: DesignTokens.cardVerticalInset,
      width: DesignTokens.cardStatusWidth,
      height: DesignTokens.cardDetailHeight
    )
    metadataLabel.frame = NSRect(
      x: DesignTokens.cardContentLeading + DesignTokens.cardStatusWidth,
      y: DesignTokens.cardVerticalInset,
      width: bounds.width
        - DesignTokens.cardContentLeading
        - DesignTokens.cardStatusWidth
        - DesignTokens.cardContentTrailing,
      height: DesignTokens.cardDetailHeight
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    let cardPath = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      xRadius: DesignTokens.cornerCard,
      yRadius: DesignTokens.cornerCard
    )
    DesignTokens.surfaceFloating.setFill()
    cardPath.fill()
    DesignTokens.strokeColor.setStroke()
    cardPath.lineWidth = DesignTokens.strokeSubtle
    cardPath.stroke()

    let accent = NSBezierPath(
      roundedRect: NSRect(
        x: DesignTokens.cardAccentLeading,
        y: DesignTokens.cardVerticalInset,
        width: DesignTokens.cardAccentWidth,
        height: bounds.height - DesignTokens.cardVerticalInset * 2
      ),
      xRadius: DesignTokens.cardAccentWidth / 2,
      yRadius: DesignTokens.cardAccentWidth / 2
    )
    statusColor(presentation.status).setFill()
    accent.fill()

    if presentation.task.hasUnseenCompletion {
      DesignTokens.statusCompleted.setFill()
      NSBezierPath(
        ovalIn: NSRect(
          x: bounds.maxX - DesignTokens.cardVerticalInset - DesignTokens.resultDotSize,
          y: bounds.maxY - DesignTokens.cardVerticalInset - DesignTokens.resultDotSize,
          width: DesignTokens.resultDotSize,
          height: DesignTokens.resultDotSize
        )
      ).fill()
    }
  }
}

@MainActor
final class TaskListDocumentView: NSView {
  private var cardViews: [TaskCardView] = []

  override var isFlipped: Bool { true }

  func update(
    cards: [TaskCardPresentation],
    onOpen: @escaping (AgentTaskSnapshot) -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    for cardView in cardViews {
      cardView.removeFromSuperview()
    }
    cardViews = cards.map {
      TaskCardView(presentation: $0, onOpen: onOpen, onDragEnded: onDragEnded)
    }
    cardViews.forEach(addSubview)
    frame.size = NSSize(width: DesignTokens.cardWidth, height: contentHeight)
    needsLayout = true
  }

  var contentHeight: CGFloat {
    guard !cardViews.isEmpty else { return 0 }
    return CGFloat(cardViews.count) * DesignTokens.cardHeight
      + CGFloat(cardViews.count - 1) * DesignTokens.spaceS
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 0
    for cardView in cardViews {
      cardView.frame = NSRect(
        x: 0,
        y: y,
        width: DesignTokens.cardWidth,
        height: DesignTokens.cardHeight
      )
      y += DesignTokens.cardHeight + DesignTokens.spaceS
    }
  }
}

@MainActor
final class OverlayContainerView: NSView {
  let petView = PetView(frame: NSRect(origin: .zero, size: DesignTokens.petSize))
  let disclosureButton = NSButton(title: "", target: nil, action: nil)
  private let scrollView = NSScrollView()
  private let taskListView = TaskListDocumentView()
  private(set) var preferredSize = DesignTokens.petSize
  private(set) var isPetHidden = false
  private var animationsActive = true
  private var cardsHeight: CGFloat = 0
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
    onOpen: @escaping (AgentTaskSnapshot) -> Void,
    onPetClick: @escaping () -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    petView.update(with: presentation)
    petView.onClick = presentation.canToggleExpansion ? onPetClick : nil
    petView.onDragEnded = onDragEnded
    toggleExpansion = onPetClick
    taskListView.update(cards: presentation.cards, onOpen: onOpen, onDragEnded: onDragEnded)
    cardsHeight = min(
      taskListView.contentHeight,
      CGFloat(DesignTokens.maximumVisibleCards) * DesignTokens.cardHeight
        + CGFloat(DesignTokens.maximumVisibleCards - 1) * DesignTokens.spaceS
    )
    scrollView.hasVerticalScroller = taskListView.contentHeight > cardsHeight
    scrollView.isHidden = presentation.cards.isEmpty
    let showsDisclosure =
      isPetHidden && presentation.canToggleExpansion && !presentation.cards.isEmpty
    disclosureButton.isHidden = !showsDisclosure
    disclosureButton.image = NSImage(
      systemSymbolName: presentation.isTemporarilyExpanded ? "chevron.up" : "chevron.down",
      accessibilityDescription: nil
    )
    disclosureButton.setAccessibilityLabel(
      presentation.isTemporarilyExpanded ? "Show fewer agent tasks" : "Show all agent tasks")
    let disclosureHeight = showsDisclosure ? DesignTokens.cardDisclosureHeight : 0
    if isPetHidden {
      preferredSize = NSSize(
        width: presentation.cards.isEmpty ? 0 : DesignTokens.cardWidth,
        height: presentation.cards.isEmpty ? 0 : cardsHeight + disclosureHeight
      )
    } else {
      preferredSize = NSSize(
        width: DesignTokens.petSize.width
          + (presentation.cards.isEmpty ? 0 : DesignTokens.spaceM + DesignTokens.cardWidth),
        height: max(DesignTokens.petSize.height, cardsHeight)
      )
    }
    frame.size = preferredSize
    needsLayout = true
  }

  override func layout() {
    super.layout()
    petView.frame = NSRect(origin: .zero, size: DesignTokens.petSize)
    guard !scrollView.isHidden else { return }
    let cardsX = isPetHidden ? 0 : DesignTokens.petSize.width + DesignTokens.spaceM
    scrollView.frame = NSRect(
      x: cardsX,
      y: 0,
      width: DesignTokens.cardWidth,
      height: isPetHidden ? cardsHeight : preferredSize.height
    )
    taskListView.frame.size.width = DesignTokens.cardWidth
    if !disclosureButton.isHidden {
      disclosureButton.frame = NSRect(
        x: cardsX,
        y: cardsHeight,
        width: DesignTokens.cardWidth,
        height: DesignTokens.cardDisclosureHeight
      )
    }
  }

  @objc private func disclosureClicked() {
    toggleExpansion?()
  }
}

@MainActor
func statusColor(_ status: TaskVisualStatus) -> NSColor {
  switch status {
  case .inputNeeded: DesignTokens.statusWaiting
  case .working: DesignTokens.statusWorking
  case .finished: DesignTokens.statusCompleted
  case .failed: DesignTokens.statusFailed
  case .stopped, .ready: DesignTokens.statusUnknown
  }
}

extension TaskVisualStatus {
  var petAnimationState: PetAnimationState {
    switch self {
    case .inputNeeded: .waiting
    case .working: .running
    case .finished: .review
    case .failed: .failed
    case .stopped, .ready: .idle
    }
  }
}
