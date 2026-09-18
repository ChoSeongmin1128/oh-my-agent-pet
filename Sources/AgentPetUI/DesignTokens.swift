import AppKit

@MainActor
public enum DesignTokens {
  public static let spaceXS: CGFloat = 4
  public static let spaceS: CGFloat = 6
  public static let spaceM: CGFloat = 10
  public static let spaceL: CGFloat = 16

  public static let petSize = NSSize(width: 78, height: 78)
  public static let cardWidth: CGFloat = 268
  public static let cardHeight: CGFloat = 60
  public static let cardContentLeading: CGFloat = 20
  public static let cardContentTrailing: CGFloat = 14
  public static let cardVerticalInset: CGFloat = 10
  public static let cardTitleHeight: CGFloat = 18
  public static let cardDetailHeight: CGFloat = 16
  public static let cardStatusWidth: CGFloat = 100
  public static let cardAccentLeading: CGFloat = 5
  public static let cardAccentWidth: CGFloat = 4
  public static let resultDotSize: CGFloat = 8
  public static let maximumVisibleCards = 5
  public static let screenMargin: CGFloat = 18
  public static let cardDisclosureHeight: CGFloat = 16
  public static let cornerCard: CGFloat = 18
  public static let cardDepthLayerOffset: CGFloat = 4
  public static let cornerControl: CGFloat = 6
  public static let strokeSubtle: CGFloat = 1
  public static let dragActivationDistance: CGFloat = 5
  public static let longPressDuration: TimeInterval = 0.35

  public static let textPrimary = NSColor.white
  public static let textMuted = NSColor.white.withAlphaComponent(0.52)
  public static let surfaceFloating = NSColor(calibratedWhite: 0.105, alpha: 1)
  public static let surfaceCardDepth = NSColor(calibratedWhite: 0.16, alpha: 1)
  public static let strokeColor = NSColor.white.withAlphaComponent(0.10)
  public static let statusWorking = NSColor.systemBlue
  public static let statusWaiting = NSColor.systemYellow
  public static let statusFailed = NSColor.systemRed
  public static let statusCompleted = NSColor.systemGreen
  public static let statusUnknown = NSColor.systemGray
  public static let petBody = NSColor(
    calibratedRed: 0.48,
    green: 0.60,
    blue: 0.98,
    alpha: 1
  )
  public static let petFace = NSColor(calibratedWhite: 0.12, alpha: 0.9)

  public static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
  public static let statusFont = NSFont.systemFont(ofSize: 11, weight: .medium)
  public static let metadataFont = NSFont.systemFont(ofSize: 10, weight: .medium)

  public static let settingsWindowSize = NSSize(width: 580, height: 540)
  public static let settingsPaneInset: CGFloat = 20
  public static let settingsSectionSpacing: CGFloat = 18
  public static let settingsRowSpacing: CGFloat = 8
  public static let settingsRowMinimumHeight: CGFloat = 28
  public static let settingsPreviewSize: CGFloat = 156
  public static let settingsThumbnailSize: CGFloat = 40
  public static let settingsChipCornerRadius: CGFloat = 5
  public static let settingsSectionCornerRadius: CGFloat = 10
  public static let settingsSurfaceOpacity: CGFloat = 0.5
}
