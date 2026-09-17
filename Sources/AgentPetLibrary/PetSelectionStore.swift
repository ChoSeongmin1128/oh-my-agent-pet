import Foundation

public enum PetSelection: Equatable, Sendable {
  case original
  case none
  case installed(recordID: String)

  public static let originalIdentifier = "original"
  public static let noneIdentifier = "none"
  public static let reservedIdentifiers: Set<String> = [originalIdentifier, noneIdentifier]

  public var identifier: String {
    switch self {
    case .original: Self.originalIdentifier
    case .none: Self.noneIdentifier
    case .installed(let recordID): recordID
    }
  }

  public var installedRecordID: String? {
    if case .installed(let recordID) = self { return recordID }
    return nil
  }
}

public enum PetSelectionStoreIssue: Equatable, Sendable {
  case corruptFile
  case unsupportedSchema(Int)
}

public struct PetSelectionLoad: Equatable, Sendable {
  public let selection: PetSelection
  public let issue: PetSelectionStoreIssue?

  public init(selection: PetSelection, issue: PetSelectionStoreIssue? = nil) {
    self.selection = selection
    self.issue = issue
  }
}

struct PetSelectionStore: Sendable {
  static let currentSchemaVersion = 1

  let url: URL
  let fileSystem: PetLibraryFileSystem

  func load() -> PetSelectionLoad {
    guard fileSystem.itemType(at: url) == .regularFile else {
      return PetSelectionLoad(selection: .original)
    }
    guard let data = try? fileSystem.readData(at: url, maximumBytes: 4_096),
      let stored = try? JSONDecoder().decode(StoredSelection.self, from: data)
    else {
      return PetSelectionLoad(selection: .original, issue: .corruptFile)
    }
    guard stored.schemaVersion == Self.currentSchemaVersion else {
      return PetSelectionLoad(
        selection: .original, issue: .unsupportedSchema(stored.schemaVersion))
    }
    switch stored.kind {
    case PetSelection.originalIdentifier:
      return PetSelectionLoad(selection: .original)
    case PetSelection.noneIdentifier:
      return PetSelectionLoad(selection: .none)
    case "installed":
      guard let recordID = stored.recordID, PetRecordIdentifier.isValid(recordID) else {
        return PetSelectionLoad(selection: .original, issue: .corruptFile)
      }
      return PetSelectionLoad(selection: .installed(recordID: recordID))
    default:
      return PetSelectionLoad(selection: .original, issue: .corruptFile)
    }
  }

  func save(_ selection: PetSelection) throws {
    if case .unsupportedSchema(let version)? = load().issue {
      throw PetLibraryError(.selectionStoreUnsupported, detail: ["schemaVersion": "\(version)"])
    }
    let stored = StoredSelection(
      schemaVersion: Self.currentSchemaVersion,
      kind: selection.installedRecordID == nil ? selection.identifier : "installed",
      recordID: selection.installedRecordID
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      try fileSystem.createDirectory(at: url.deletingLastPathComponent())
      try fileSystem.writeData(try encoder.encode(stored), to: url)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["target": "selection"])
    }
  }

  private struct StoredSelection: Codable {
    let schemaVersion: Int
    let kind: String
    let recordID: String?
  }
}

enum PetRecordIdentifier {
  static func isValid(_ value: String) -> Bool {
    // Record IDs become directory names, so they follow the manifest identifier rules exactly.
    guard value.count <= 64 + 1 + PetLibraryPolicy.recordIdentifierSuffixLength * 2 else {
      return false
    }
    return !value.hasPrefix(".")
      && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0)
          || CharacterSet(charactersIn: "-_.").contains($0)
      }
  }
}
