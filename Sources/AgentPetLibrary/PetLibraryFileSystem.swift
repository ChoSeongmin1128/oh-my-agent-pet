import Foundation

public enum PetLibraryItemType: Equatable, Sendable {
  case missing
  case regularFile
  case directory
  case symbolicLink
  case other
}

public protocol PetLibraryFileSystem: Sendable {
  func itemType(at url: URL) -> PetLibraryItemType
  func fileSize(at url: URL) throws -> Int
  func contentsOfDirectory(at url: URL) throws -> [URL]
  func createDirectory(at url: URL) throws
  func copyFile(at source: URL, to destination: URL) throws
  func moveItem(at source: URL, to destination: URL) throws
  func removeItem(at url: URL) throws
  func readData(at url: URL, maximumBytes: Int) throws -> Data
  func writeData(_ data: Data, to url: URL) throws
}

public struct DefaultPetLibraryFileSystem: PetLibraryFileSystem {
  public init() {}

  public func itemType(at url: URL) -> PetLibraryItemType {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
      return .missing
    }
    switch attributes[.type] as? FileAttributeType {
    case .typeRegular?: return .regularFile
    case .typeDirectory?: return .directory
    case .typeSymbolicLink?: return .symbolicLink
    default: return .other
    }
  }

  public func fileSize(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.intValue ?? 0
  }

  public func contentsOfDirectory(at url: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: []
    )
  }

  public func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  public func copyFile(at source: URL, to destination: URL) throws {
    try FileManager.default.copyItem(at: source, to: destination)
  }

  public func moveItem(at source: URL, to destination: URL) throws {
    try FileManager.default.moveItem(at: source, to: destination)
  }

  public func removeItem(at url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }

  public func readData(at url: URL, maximumBytes: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "file_too_large"])
    }
    return data
  }

  public func writeData(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic])
  }
}
