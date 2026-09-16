import Foundation

public enum ExecutionSurface: String, Codable, Hashable, Sendable {
  case desktop
  case terminal
}

public struct TaskNavigationTarget: Codable, Hashable, Sendable {
  public let surface: ExecutionSurface
  public let applicationBundleIdentifier: String
  public let deepLink: String?
  public let terminalSessionID: String?
  public let tty: String?

  public init(
    surface: ExecutionSurface,
    applicationBundleIdentifier: String,
    deepLink: String? = nil,
    terminalSessionID: String? = nil,
    tty: String? = nil
  ) {
    self.surface = surface
    self.applicationBundleIdentifier = applicationBundleIdentifier
    self.deepLink = deepLink
    self.terminalSessionID = terminalSessionID
    self.tty = tty
  }
}
