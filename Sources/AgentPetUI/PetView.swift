import AgentPetCore
import AgentPetSprites
import AppKit

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
    setAccessibilityLabel("\(AgentPetProduct.name), \(status.label)")
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
