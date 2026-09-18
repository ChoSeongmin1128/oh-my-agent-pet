import Foundation

public struct OverlayPosition: Codable, Equatable, Sendable {
  // Stable overlay anchor in screen coordinates. With a visible pet this is the
  // pet's lower-left origin; in card-only mode it is the panel/card lower-left origin.
  // Legacy horizontal-layout values used the panel origin, which was also the pet origin.
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public enum OverlayLayout: String, Codable, CaseIterable, Sendable {
  case vertical
  case horizontal

  public static let defaultValue: Self = .vertical
}

public struct OverlayPreferences: Equatable, Sendable {
  public static let defaultCardDepthHintEnabled = true

  public var isVisible: Bool
  public var cardMode: CardDisplayMode
  public var layout: OverlayLayout
  public var isCardDepthHintEnabled: Bool
  public var position: OverlayPosition?

  public init(
    isVisible: Bool = true,
    cardMode: CardDisplayMode = .one,
    layout: OverlayLayout = .defaultValue,
    isCardDepthHintEnabled: Bool = Self.defaultCardDepthHintEnabled,
    position: OverlayPosition? = nil
  ) {
    self.isVisible = isVisible
    self.cardMode = cardMode
    self.layout = layout
    self.isCardDepthHintEnabled = isCardDepthHintEnabled
    self.position = position
  }
}

@MainActor
public final class OverlayPreferencesStore {
  public static let currentSchemaVersion = 1

  private enum Key {
    static let schemaVersion = "overlay.schemaVersion"
    static let isVisible = "overlay.isVisible"
    static let cardMode = "overlay.cardMode"
    static let layout = "overlay.layout"
    static let cardDepthHintEnabled = "overlay.cardDepthHintEnabled"
    static let positionX = "overlay.position.x"
    static let positionY = "overlay.position.y"
  }

  private let defaults: UserDefaults

  public convenience init() {
    self.init(defaults: .standard)
  }

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  public func load() -> OverlayPreferences {
    let version = defaults.integer(forKey: Key.schemaVersion)
    guard version == 0 || version == Self.currentSchemaVersion else {
      return OverlayPreferences()
    }
    let isVisible = defaults.object(forKey: Key.isVisible) as? Bool ?? true
    let cardMode = defaults.string(forKey: Key.cardMode).flatMap(CardDisplayMode.init) ?? .one
    let layout =
      defaults.string(forKey: Key.layout).flatMap(OverlayLayout.init) ?? .defaultValue
    let isCardDepthHintEnabled =
      defaults.object(forKey: Key.cardDepthHintEnabled) as? Bool
      ?? OverlayPreferences.defaultCardDepthHintEnabled
    let position: OverlayPosition?
    let positionX = defaults.double(forKey: Key.positionX)
    let positionY = defaults.double(forKey: Key.positionY)
    if defaults.object(forKey: Key.positionX) != nil,
      defaults.object(forKey: Key.positionY) != nil,
      positionX.isFinite,
      positionY.isFinite
    {
      position = OverlayPosition(x: positionX, y: positionY)
    } else {
      position = nil
    }
    return OverlayPreferences(
      isVisible: isVisible,
      cardMode: cardMode,
      layout: layout,
      isCardDepthHintEnabled: isCardDepthHintEnabled,
      position: position
    )
  }

  public func save(_ preferences: OverlayPreferences) {
    let storedVersion = defaults.integer(forKey: Key.schemaVersion)
    guard storedVersion == 0 || storedVersion == Self.currentSchemaVersion else { return }
    defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
    defaults.set(preferences.isVisible, forKey: Key.isVisible)
    defaults.set(preferences.cardMode.rawValue, forKey: Key.cardMode)
    defaults.set(preferences.layout.rawValue, forKey: Key.layout)
    defaults.set(preferences.isCardDepthHintEnabled, forKey: Key.cardDepthHintEnabled)
    if let position = preferences.position {
      defaults.set(position.x, forKey: Key.positionX)
      defaults.set(position.y, forKey: Key.positionY)
    } else {
      defaults.removeObject(forKey: Key.positionX)
      defaults.removeObject(forKey: Key.positionY)
    }
  }
}
