import Foundation

public struct ProviderIdentifier: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return nil
    }
    self.rawValue = normalized
  }
}

extension ProviderIdentifier: CustomStringConvertible {
  public var description: String { rawValue }
}
