import AppKit

@MainActor
enum VectorPetRenderer {
  // The vector pet is authored at the overlay pet size. Larger surfaces such as the settings
  // preview scale the whole drawing instead of moving individual features.
  static func draw(in bounds: NSRect, status: TaskVisualStatus) {
    let baseSize = DesignTokens.petSize
    let scale = min(bounds.width / baseSize.width, bounds.height / baseSize.height)
    let transform = NSAffineTransform()
    transform.translateX(
      by: bounds.midX - baseSize.width * scale / 2,
      yBy: bounds.midY - baseSize.height * scale / 2
    )
    transform.scale(by: scale)
    NSGraphicsContext.saveGraphicsState()
    transform.concat()
    drawAtBaseSize(in: NSRect(origin: .zero, size: baseSize), status: status)
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func drawAtBaseSize(in bounds: NSRect, status: TaskVisualStatus) {
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
    drawMouth(in: bodyRect, status: status)
    drawStatusMark(in: bodyRect, status: status)
  }

  static func drawStatusMark(in rect: NSRect, status: TaskVisualStatus) {
    statusColor(status).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.minX + 5, y: rect.minY + 5, width: 9, height: 9)).fill()
  }

  static func thumbnail(size: CGFloat, status: TaskVisualStatus) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      MainActor.assumeIsolated {
        draw(in: rect, status: status)
      }
      return true
    }
  }

  private static func drawMouth(in rect: NSRect, status: TaskVisualStatus) {
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
}
