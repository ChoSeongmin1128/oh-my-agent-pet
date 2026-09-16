import AgentPetCore
import AppKit

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

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  required init?(coder: NSCoder) { nil }

  func update(with presentation: OverlayPresentation) {
    status = presentation.petStatus
    interventionCount = presentation.additionalInterventionCount
    showsCompletionDot = presentation.showsPetCompletionDot
    canExpand = presentation.canExpandFromPet
    setAccessibilityRole(canExpand ? .button : .group)
    setAccessibilityLabel("Oh My Agent Pet, \(status.label)")
    setAccessibilityHelp(canExpand ? "Show or hide all agent tasks" : "Agent task status")
    needsDisplay = true
  }

  override func accessibilityPerformPress() -> Bool {
    guard canExpand else { return false }
    onClick?()
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let bodyRect = bounds.insetBy(dx: 8, dy: 8)
    let earSize: CGFloat = 20
    let leftEar = NSBezierPath()
    leftEar.move(to: NSPoint(x: bodyRect.minX + 7, y: bodyRect.maxY - 17))
    leftEar.line(to: NSPoint(x: bodyRect.minX + 13, y: bodyRect.maxY + earSize - 8))
    leftEar.line(to: NSPoint(x: bodyRect.minX + 28, y: bodyRect.maxY - 10))
    leftEar.close()
    let rightEar = NSBezierPath()
    rightEar.move(to: NSPoint(x: bodyRect.maxX - 28, y: bodyRect.maxY - 10))
    rightEar.line(to: NSPoint(x: bodyRect.maxX - 13, y: bodyRect.maxY + earSize - 8))
    rightEar.line(to: NSPoint(x: bodyRect.maxX - 7, y: bodyRect.maxY - 17))
    rightEar.close()
    DesignTokens.petBody.setFill()
    leftEar.fill()
    rightEar.fill()
    NSBezierPath(roundedRect: bodyRect, xRadius: 25, yRadius: 25).fill()

    DesignTokens.petFace.setFill()
    let eyeY = bodyRect.midY + 7
    NSBezierPath(ovalIn: NSRect(x: bodyRect.midX - 17, y: eyeY, width: 6, height: 8)).fill()
    NSBezierPath(ovalIn: NSRect(x: bodyRect.midX + 11, y: eyeY, width: 6, height: 8)).fill()
    drawMouth(in: bodyRect)
    drawStatusMark(in: bodyRect)
    drawBadge()
  }

  private func drawMouth(in rect: NSRect) {
    let path = NSBezierPath()
    path.lineWidth = 2.2
    path.lineCapStyle = .round
    DesignTokens.petFace.setStroke()
    switch status {
    case .failed, .stopped:
      path.move(to: NSPoint(x: rect.midX - 6, y: rect.midY - 8))
      path.curve(
        to: NSPoint(x: rect.midX + 6, y: rect.midY - 8),
        controlPoint1: NSPoint(x: rect.midX - 2, y: rect.midY - 2),
        controlPoint2: NSPoint(x: rect.midX + 2, y: rect.midY - 2)
      )
    case .inputNeeded:
      path.appendOval(in: NSRect(x: rect.midX - 3, y: rect.midY - 10, width: 6, height: 7))
    default:
      path.move(to: NSPoint(x: rect.midX - 7, y: rect.midY - 5))
      path.curve(
        to: NSPoint(x: rect.midX + 7, y: rect.midY - 5),
        controlPoint1: NSPoint(x: rect.midX - 3, y: rect.midY - 12),
        controlPoint2: NSPoint(x: rect.midX + 3, y: rect.midY - 12)
      )
    }
    path.stroke()
  }

  private func drawStatusMark(in rect: NSRect) {
    let color = statusColor(status)
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.minX + 5, y: rect.minY + 5, width: 9, height: 9)).fill()
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
  private let scrollView = NSScrollView()
  private let taskListView = TaskListDocumentView()
  private(set) var preferredSize = DesignTokens.petSize

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = taskListView
    addSubview(petView)
    addSubview(scrollView)
  }

  required init?(coder: NSCoder) { nil }

  func update(
    presentation: OverlayPresentation,
    onOpen: @escaping (AgentTaskSnapshot) -> Void,
    onPetClick: @escaping () -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    petView.update(with: presentation)
    petView.onClick = presentation.canExpandFromPet ? onPetClick : nil
    petView.onDragEnded = onDragEnded
    taskListView.update(cards: presentation.cards, onOpen: onOpen, onDragEnded: onDragEnded)
    let cardHeight = min(
      taskListView.contentHeight,
      CGFloat(DesignTokens.maximumVisibleCards) * DesignTokens.cardHeight
        + CGFloat(DesignTokens.maximumVisibleCards - 1) * DesignTokens.spaceS
    )
    scrollView.hasVerticalScroller = taskListView.contentHeight > cardHeight
    scrollView.isHidden = presentation.cards.isEmpty
    preferredSize = NSSize(
      width: DesignTokens.petSize.width
        + (presentation.cards.isEmpty ? 0 : DesignTokens.spaceM + DesignTokens.cardWidth),
      height: max(DesignTokens.petSize.height, cardHeight)
    )
    frame.size = preferredSize
    needsLayout = true
  }

  override func layout() {
    super.layout()
    petView.frame = NSRect(origin: .zero, size: DesignTokens.petSize)
    guard !scrollView.isHidden else { return }
    scrollView.frame = NSRect(
      x: DesignTokens.petSize.width + DesignTokens.spaceM,
      y: 0,
      width: DesignTokens.cardWidth,
      height: preferredSize.height
    )
    taskListView.frame.size.width = DesignTokens.cardWidth
  }
}

@MainActor
private func statusColor(_ status: TaskVisualStatus) -> NSColor {
  switch status {
  case .inputNeeded: DesignTokens.statusWaiting
  case .working: DesignTokens.statusWorking
  case .finished: DesignTokens.statusCompleted
  case .failed: DesignTokens.statusFailed
  case .stopped, .ready: DesignTokens.statusUnknown
  }
}
