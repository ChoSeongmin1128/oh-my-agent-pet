import Foundation

struct CodexDateParser {
  private let fractional: ISO8601DateFormatter
  private let standard: ISO8601DateFormatter

  init() {
    fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    standard = ISO8601DateFormatter()
  }

  func parse(_ value: String?) -> Date? {
    guard let value else { return nil }
    return fractional.date(from: value) ?? standard.date(from: value)
  }
}
