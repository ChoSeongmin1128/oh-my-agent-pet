import Foundation

public enum AgentPetProduct {
  public static let name = "Oh My Agent Pet"
  public static let bundleIdentifier = "com.seongmin.OhMyAgentPet"
  public static let cliName = "omapet"
  public static let developmentVersion = "0.0.0-dev"
  public static let hookOwnershipMarker = "\(name) session observer"
}

public struct ApplicationPaths: Equatable, Sendable {
  public let applicationSupportDirectory: URL
  public let eventsURL: URL
  public let petsDirectory: URL

  public init(homeDirectory: URL) {
    applicationSupportDirectory = homeDirectory.appendingPathComponent(
      "Library/Application Support/\(AgentPetProduct.name)",
      isDirectory: true
    )
    eventsURL = applicationSupportDirectory.appendingPathComponent("events.ndjson")
    petsDirectory = applicationSupportDirectory.appendingPathComponent("Pets", isDirectory: true)
  }

  public static func companionCLIURL(appExecutableURL: URL) -> URL {
    appExecutableURL.deletingLastPathComponent()
      .appendingPathComponent(AgentPetProduct.cliName, isDirectory: false)
  }
}
