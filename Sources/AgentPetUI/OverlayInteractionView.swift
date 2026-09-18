import AgentPetCore
import AgentPetSprites
import AppKit

final class GazeRefreshGate: @unchecked Sendable {
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
