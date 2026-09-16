import Foundation

public struct OverlayPosition: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct OverlayPreferences: Equatable, Sendable {
  public var isVisible: Bool
  public var cardMode: CardDisplayMode
  public var position: OverlayPosition?

  public init(
    isVisible: Bool = true,
    cardMode: CardDisplayMode = .one,
    position: OverlayPosition? = nil
  ) {
    self.isVisible = isVisible
    self.cardMode = cardMode
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
    return OverlayPreferences(isVisible: isVisible, cardMode: cardMode, position: position)
  }

  public func save(_ preferences: OverlayPreferences) {
    let storedVersion = defaults.integer(forKey: Key.schemaVersion)
    guard storedVersion == 0 || storedVersion == Self.currentSchemaVersion else { return }
    defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
    defaults.set(preferences.isVisible, forKey: Key.isVisible)
    defaults.set(preferences.cardMode.rawValue, forKey: Key.cardMode)
    if let position = preferences.position {
      defaults.set(position.x, forKey: Key.positionX)
      defaults.set(position.y, forKey: Key.positionY)
    } else {
      defaults.removeObject(forKey: Key.positionX)
      defaults.removeObject(forKey: Key.positionY)
    }
  }
}
