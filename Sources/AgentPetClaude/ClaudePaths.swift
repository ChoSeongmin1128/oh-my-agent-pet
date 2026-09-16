import Foundation

public struct ClaudePaths: Sendable {
  public let configRoot: URL
  public let settingsURL: URL
  public let applicationSupportDirectory: URL
  public let eventsURL: URL

  public init(homeDirectory: URL, environment: [String: String]) {
    configRoot = Self.configRoot(homeDirectory: homeDirectory, environment: environment)
    settingsURL = configRoot.appendingPathComponent("settings.json")
    applicationSupportDirectory =
      homeDirectory
      .appendingPathComponent("Library/Application Support/Oh My Agent Pet", isDirectory: true)
    eventsURL = applicationSupportDirectory.appendingPathComponent("events.ndjson")
  }

  private static func configRoot(
    homeDirectory: URL,
    environment: [String: String]
  ) -> URL {
    guard let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty else {
      return homeDirectory.appendingPathComponent(".claude", isDirectory: true)
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
