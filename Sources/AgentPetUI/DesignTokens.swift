import AppKit

@MainActor
public enum DesignTokens {
  public static let compactSpacing: CGFloat = 6
  public static let standardSpacing: CGFloat = 10
  public static let minimumHitTarget: CGFloat = 28

  public static let primaryText = NSColor.labelColor
  public static let secondaryText = NSColor.secondaryLabelColor
  public static let cardBackground = NSColor.windowBackgroundColor
}
