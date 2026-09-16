import CoreGraphics
import Foundation

public enum OverlayPointerIntent: Equatable, Sendable {
  case click
  case drag
  case hold
}

public struct OverlayPointerIntentResolver: Sendable {
  public let dragDistance: CGFloat
  public let holdDuration: TimeInterval

  public init(dragDistance: CGFloat, holdDuration: TimeInterval) {
    self.dragDistance = dragDistance
    self.holdDuration = holdDuration
  }

  public func resolve(distance: CGFloat, duration: TimeInterval) -> OverlayPointerIntent {
    if distance >= dragDistance { return .drag }
    if duration >= holdDuration { return .hold }
    return .click
  }
}
