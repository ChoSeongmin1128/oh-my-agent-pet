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

  private init(knownValue: String) {
    rawValue = knownValue
  }

  public static let claude = ProviderIdentifier(knownValue: "claude")
  public static let codex = ProviderIdentifier(knownValue: "codex")

  public var displayName: String {
    ProviderCatalog.descriptor(for: self)?.displayName ?? rawValue
  }
}

public struct ProviderDescriptor: Equatable, Sendable {
  public let identifier: ProviderIdentifier
  public let displayName: String

  public init(identifier: ProviderIdentifier, displayName: String) {
    self.identifier = identifier
    self.displayName = displayName
  }
}

public enum ProviderCatalog {
  public static let supported: [ProviderDescriptor] = [
    ProviderDescriptor(identifier: .claude, displayName: "Claude"),
    ProviderDescriptor(identifier: .codex, displayName: "Codex"),
  ]

  public static func descriptor(for identifier: ProviderIdentifier) -> ProviderDescriptor? {
    supported.first { $0.identifier == identifier }
  }
}

extension ProviderIdentifier: CustomStringConvertible {
  public var description: String { rawValue }
}
