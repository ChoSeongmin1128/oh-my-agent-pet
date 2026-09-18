import AgentPetSprites
import Foundation

public enum PetPackageSource: Equatable, Sendable {
  case folder(URL)
  case archive(URL)
  case url(URL)
}

public enum PetPackageSourceResolver {
  public static func resolve(
    _ input: String,
    relativeTo directory: URL,
    fileSystem: PetLibraryFileSystem = DefaultPetLibraryFileSystem()
  ) throws -> PetPackageSource {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "empty_input"])
    }
    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme)
    {
      return .url(url)
    }
    let fileURL = URL(fileURLWithPath: trimmed, relativeTo: directory)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    switch fileSystem.itemType(at: fileURL) {
    case .directory:
      return .folder(fileURL)
    case .regularFile:
      guard fileURL.pathExtension.lowercased() == "zip" else {
        throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_package"])
      }
      return .archive(fileURL)
    case .missing:
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "missing"])
    case .symbolicLink, .other:
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_package"])
    }
  }
}

public enum PetInspectionWarning: String, Equatable, Sendable {
  case licenseUnknown = "license_unknown"
  case duplicateAsset = "duplicate_asset"
  case manifestIDInUse = "manifest_id_in_use"
}

public struct PetInspection: Equatable, Sendable {
  public let manifestID: String
  public let displayName: String
  public let description: String
  public let spriteVersion: Int
  public let spritesheetPath: String
  public let source: PetInstallSource
  public let packageFingerprint: String
  public let spritesheetFingerprint: String
  public let license: PetLicenseDeclaration
  public let licenseStatus: PetLicenseStatus
  public let warnings: [PetInspectionWarning]
  public let duplicateOf: String?
  public let proposedRecordID: String
}

public struct PetStagedPackage: Sendable {
  let stageDirectory: URL
  public let packageDirectory: URL
  public let inspection: PetInspection
  public let package: PetSpritePackage
}

public struct PetInstallOutcome: Equatable, Sendable {
  public let record: PetLibraryRecord
  public let alreadyInstalled: Bool
}

public struct PetRemoveOutcome: Equatable, Sendable {
  public let recordID: String
  public let selectionReset: Bool
}

public enum PetLibraryEntryIssue: Equatable, Sendable {
  case recordUnreadable
  case packageFilesMissing
}

public struct PetLibraryEntry: Equatable, Sendable {
  public let recordID: String
  public let record: PetLibraryRecord?
  public let issue: PetLibraryEntryIssue?
  public let packageDirectory: URL
}

public enum PetSelectionIssue: Equatable, Sendable {
  case recordMissing(recordID: String)
  case packageDamaged(recordID: String, code: PetLibraryError.Code)
  case selectionFileCorrupt
  case selectionSchemaUnsupported(Int)
}

public struct PetSelectionResolution: Sendable {
  public let selection: PetSelection
  public let record: PetLibraryRecord?
  public let package: PetSpritePackage?
  public let issue: PetSelectionIssue?
}
