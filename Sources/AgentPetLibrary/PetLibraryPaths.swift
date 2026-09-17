import Foundation

public struct PetLibraryPaths: Equatable, Sendable {
  public static let packageDirectoryName = "package"
  public static let recordFileName = "record.json"

  public let rootDirectory: URL
  public let libraryDirectory: URL
  public let stagingDirectory: URL
  public let selectionURL: URL

  public init(applicationSupportDirectory: URL) {
    rootDirectory = applicationSupportDirectory.appendingPathComponent("Pets", isDirectory: true)
    libraryDirectory = rootDirectory.appendingPathComponent("library", isDirectory: true)
    stagingDirectory = rootDirectory.appendingPathComponent("staging", isDirectory: true)
    selectionURL = rootDirectory.appendingPathComponent("selection.json", isDirectory: false)
  }

  public func recordDirectory(for recordID: String) -> URL {
    libraryDirectory.appendingPathComponent(recordID, isDirectory: true)
  }

  public func packageDirectory(for recordID: String) -> URL {
    recordDirectory(for: recordID)
      .appendingPathComponent(Self.packageDirectoryName, isDirectory: true)
  }

  public func recordFile(for recordID: String) -> URL {
    recordDirectory(for: recordID).appendingPathComponent(Self.recordFileName, isDirectory: false)
  }
}
