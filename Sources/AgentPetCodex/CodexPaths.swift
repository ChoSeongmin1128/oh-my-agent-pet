import Foundation

public struct CodexPaths: Sendable {
  public let dataRoot: URL
  public let sessionsDirectory: URL
  public let sessionIndexURL: URL

  public init(homeDirectory: URL, environment: [String: String]) {
    dataRoot = Self.dataRoot(homeDirectory: homeDirectory, environment: environment)
    sessionsDirectory = dataRoot.appendingPathComponent("sessions", isDirectory: true)
    sessionIndexURL = dataRoot.appendingPathComponent("session_index.jsonl")
  }

  private static func dataRoot(
    homeDirectory: URL,
    environment: [String: String]
  ) -> URL {
    guard let configured = environment["CODEX_HOME"], !configured.isEmpty else {
      return homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }
    if configured == "~" {
      return homeDirectory
    }
    if configured.hasPrefix("~/") {
      return homeDirectory.appendingPathComponent(
        String(configured.dropFirst(2)), isDirectory: true)
    }
    return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
  }
}
