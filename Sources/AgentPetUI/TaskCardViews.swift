import AgentPetCore
import AgentPetSprites
import AppKit

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
    let cardPath = CardShape.path(in: bounds)
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
enum CardShape {
  static var cornerRadius: CGFloat { DesignTokens.cornerCard }

  static func path(in bounds: NSRect) -> NSBezierPath {
    NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      xRadius: cornerRadius,
      yRadius: cornerRadius
    )
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
final class CardDepthHintView: NSView {
  private(set) var layerCount = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(false)
    isHidden = true
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func setLayerCount(_ count: Int) {
    let boundedCount = min(max(count, 0), CardDepthHintPolicy.maximumLayers)
    guard layerCount != boundedCount else { return }
    layerCount = boundedCount
    isHidden = boundedCount == 0
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard layerCount > 0 else { return }
    for layer in 0..<layerCount {
      let offset = CGFloat(layer) * DesignTokens.cardDepthLayerOffset
      let rect = NSRect(
        x: 0,
        y: 0,
        width: bounds.width,
        height: DesignTokens.cardHeight
      ).offsetBy(dx: 0, dy: offset)
      let path = CardShape.path(in: rect)
      DesignTokens.surfaceCardDepth.setFill()
      path.fill()
      DesignTokens.strokeColor.setStroke()
      path.lineWidth = DesignTokens.strokeSubtle
      path.stroke()
    }
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
