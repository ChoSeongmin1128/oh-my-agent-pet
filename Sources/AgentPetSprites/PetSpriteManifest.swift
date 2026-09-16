import Foundation

public struct PetSpriteManifest: Decodable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let description: String
  public let spriteVersionNumber: Int
  public let spritesheetPath: String

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case description
    case spriteVersionNumber
    case spritesheetPath
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    spriteVersionNumber =
      try container.decodeIfPresent(
        Int.self,
        forKey: .spriteVersionNumber
      ) ?? 1
    spritesheetPath = try container.decode(String.self, forKey: .spritesheetPath)
  }
}

public enum PetSpriteVersion: Int, Equatable, Sendable {
  case v1 = 1
  case v2 = 2

  public static let columns = 8
  public static let cellWidth = 192
  public static let cellHeight = 208

  public var rows: Int {
    switch self {
    case .v1: 9
    case .v2: 11
    }
  }

  public var pixelWidth: Int { Self.columns * Self.cellWidth }
  public var pixelHeight: Int { rows * Self.cellHeight }
  public var supportsGaze: Bool { self == .v2 }

  public var requiredFrameCounts: [Int] {
    let actionRows = [6, 8, 8, 4, 5, 8, 6, 6, 6]
    return self == .v2 ? actionRows + [8, 8] : actionRows
  }
}
