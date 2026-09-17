import AgentPetLibrary
import Foundation

struct OmapetPetCommands {
  let service: PetLibraryService
  let currentDirectory: URL

  func list(json: Bool) -> OmapetCommandResult {
    let load = service.loadSelection()
    let entries = service.entries()
    let output = PetListOutput(
      selection: PetSelectionOutput(load.selection),
      selectionIssue: load.issue.map(Self.describe),
      pets: entries.map {
        PetRecordOutput(entry: $0, selected: load.selection == .installed(recordID: $0.recordID))
      }
    )
    if json { return OmapetJSON.result(output) }
    var text = "Selection: \(load.selection.identifier)\n"
    for pet in output.pets {
      text +=
        "\(pet.recordID)\t\(pet.displayName ?? "-")\tv\(pet.spriteVersion.map(String.init) ?? "?")\t"
      text +=
        "\(pet.source.map { "\($0.kind):\($0.value)" } ?? "-")\tlicense:\(pet.licenseStatus ?? "-")"
      text += pet.health == "ready" ? "\n" : "\t\(pet.health)\n"
    }
    return OmapetCommandResult(exitCode: 0, standardOutput: text)
  }

  func inspect(source input: String, json: Bool, dryRun: Bool?) -> OmapetCommandResult {
    do {
      let staged = try service.stage(try resolve(input))
      defer { service.discard(staged) }
      let output = PetInspectionOutput(inspection: staged.inspection, dryRun: dryRun)
      if json { return OmapetJSON.result(output) }
      var text = "Pet: \(output.displayName) (\(output.manifestID), v\(output.spriteVersion))\n"
      text += "Source: \(output.source.kind) \(output.source.value)\n"
      text += "License: \(output.licenseStatus)\n"
      text += "Fingerprint: \(output.packageFingerprint)\n"
      if let duplicateOf = output.duplicateOf {
        text += "Already installed as: \(duplicateOf)\n"
      } else {
        text += "Would install as: \(output.wouldInstallAs)\n"
      }
      if !output.warnings.isEmpty {
        text += "Warnings: \(output.warnings.joined(separator: ", "))\n"
      }
      return OmapetCommandResult(exitCode: 0, standardOutput: text)
    } catch {
      return Self.failure(error, json: json)
    }
  }

  func install(source input: String, json: Bool) -> OmapetCommandResult {
    do {
      let staged = try service.stage(try resolve(input))
      let outcome = try service.install(staged)
      let output = PetInstallOutput(outcome: outcome, inspection: staged.inspection)
      if json { return OmapetJSON.result(output) }
      let mode = outcome.alreadyInstalled ? "already installed" : "installed"
      var text = "Pet \(outcome.record.recordID): \(mode)\n"
      text += "License: \(outcome.record.licenseStatus.rawValue)\n"
      text += "Next: \(output.nextCommands.joined(separator: "; "))\n"
      return OmapetCommandResult(exitCode: 0, standardOutput: text)
    } catch {
      return Self.failure(error, json: json)
    }
  }

  func select(identifier: String, json: Bool) -> OmapetCommandResult {
    let selection: PetSelection =
      switch identifier {
      case PetSelection.originalIdentifier: .original
      case PetSelection.noneIdentifier: .none
      default: .installed(recordID: identifier)
      }
    do {
      let changed = try service.select(selection)
      let output = PetSelectOutput(changed: changed, selection: PetSelectionOutput(selection))
      if json { return OmapetJSON.result(output) }
      return OmapetCommandResult(
        exitCode: 0,
        standardOutput:
          "Selection: \(selection.identifier) (\(changed ? "changed" : "unchanged"))\n"
      )
    } catch {
      return Self.failure(error, json: json)
    }
  }

  func remove(recordID: String, json: Bool) -> OmapetCommandResult {
    do {
      let outcome = try service.remove(recordID: recordID)
      let output = PetRemoveOutput(
        recordID: outcome.recordID, selectionReset: outcome.selectionReset)
      if json { return OmapetJSON.result(output) }
      var text = "Pet \(outcome.recordID): removed\n"
      if outcome.selectionReset { text += "Selection: original\n" }
      return OmapetCommandResult(exitCode: 0, standardOutput: text)
    } catch {
      return Self.failure(error, json: json)
    }
  }

  private func resolve(_ input: String) throws -> PetPackageSource {
    try PetPackageSourceResolver.resolve(input, relativeTo: currentDirectory)
  }

  private static func failure(_ error: Error, json: Bool) -> OmapetCommandResult {
    let libraryError =
      error as? PetLibraryError ?? PetLibraryError(.writeFailed, detail: ["reason": "unexpected"])
    let exitCode = Self.exitCode(for: libraryError.code)
    if json {
      return OmapetJSON.result(
        PetErrorOutput(code: libraryError.code.rawValue, detail: libraryError.detail),
        exitCode: exitCode)
    }
    let detail = libraryError.detail.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    return OmapetCommandResult(
      exitCode: exitCode,
      standardError: "Pet command failed: \(libraryError.code.rawValue)"
        + (detail.isEmpty ? "\n" : " (\(detail.joined(separator: ", ")))\n")
    )
  }

  static func exitCode(for code: PetLibraryError.Code) -> Int32 {
    switch code {
    case .invalidRecordID:
      64
    case .unsupportedSource, .invalidManifest, .unsupportedVersion, .versionDimensionMismatch,
      .missingRequiredFrame, .damagedImage, .oversizedPackage, .invalidGalleryResponse:
      65
    case .sourceUnavailable, .recordNotFound:
      66
    case .downloadFailed, .petNotFound:
      69
    case .unsafePackage, .urlNotAllowed, .redirectLimitExceeded:
      73
    case .writeFailed, .selectionStoreUnsupported:
      74
    }
  }

  private static func describe(_ issue: PetSelectionStoreIssue) -> String {
    switch issue {
    case .corruptFile: "selection_file_corrupt"
    case .unsupportedSchema: "selection_schema_unsupported"
    }
  }
}

enum OmapetJSON {
  static func result(_ value: some Encodable, exitCode: Int32 = 0) -> OmapetCommandResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(value)
      return OmapetCommandResult(
        exitCode: exitCode,
        standardOutput: String(decoding: data, as: UTF8.self) + "\n"
      )
    } catch {
      return OmapetCommandResult(exitCode: 70, standardError: "Failed to encode output.\n")
    }
  }
}

struct PetSelectionOutput: Encodable {
  let kind: String
  let recordID: String?

  init(_ selection: PetSelection) {
    kind = selection.installedRecordID == nil ? selection.identifier : "installed"
    recordID = selection.installedRecordID
  }
}

struct PetSourceOutput: Encodable {
  let kind: String
  let value: String

  init(_ source: PetInstallSource) {
    kind = source.kind
    value = source.value
  }
}

struct PetLicenseOutput: Encodable {
  let name: String?
  let url: String?
  let attribution: String?
  let noticeFile: String?

  init?(_ declaration: PetLicenseDeclaration) {
    guard !declaration.isEmpty else { return nil }
    name = declaration.name
    url = declaration.url
    attribution = declaration.attribution
    noticeFile = declaration.noticeFile
  }
}

struct PetRecordOutput: Encodable {
  let recordID: String
  let manifestID: String?
  let displayName: String?
  let spriteVersion: Int?
  let source: PetSourceOutput?
  let licenseStatus: String?
  let license: PetLicenseOutput?
  let installedAt: Date?
  let packageFingerprint: String?
  let health: String
  let selected: Bool

  init(entry: PetLibraryEntry, selected: Bool) {
    recordID = entry.recordID
    manifestID = entry.record?.manifestID
    displayName = entry.record?.displayName
    spriteVersion = entry.record?.spriteVersion
    source = entry.record.map { PetSourceOutput($0.source) }
    licenseStatus = entry.record?.licenseStatus.rawValue
    license = entry.record.flatMap { PetLicenseOutput($0.license) }
    installedAt = entry.record?.installedAt
    packageFingerprint = entry.record?.packageFingerprint
    health =
      switch entry.issue {
      case nil: "ready"
      case .recordUnreadable?: "record_unreadable"
      case .packageFilesMissing?: "package_files_missing"
      }
    self.selected = selected
  }
}

struct PetListOutput: Encodable {
  let ok = true
  let selection: PetSelectionOutput
  let selectionIssue: String?
  let pets: [PetRecordOutput]
}

struct PetInspectionOutput: Encodable {
  let ok = true
  let changed = false
  let dryRun: Bool?
  let manifestID: String
  let displayName: String
  let description: String
  let spriteVersion: Int
  let source: PetSourceOutput
  let packageFingerprint: String
  let spritesheetFingerprint: String
  let licenseStatus: String
  let license: PetLicenseOutput?
  let warnings: [String]
  let duplicateOf: String?
  let wouldInstallAs: String

  init(inspection: PetInspection, dryRun: Bool?) {
    self.dryRun = dryRun
    manifestID = inspection.manifestID
    displayName = inspection.displayName
    description = inspection.description
    spriteVersion = inspection.spriteVersion
    source = PetSourceOutput(inspection.source)
    packageFingerprint = inspection.packageFingerprint
    spritesheetFingerprint = inspection.spritesheetFingerprint
    licenseStatus = inspection.licenseStatus.rawValue
    license = PetLicenseOutput(inspection.license)
    warnings = inspection.warnings.map(\.rawValue)
    duplicateOf = inspection.duplicateOf
    wouldInstallAs = inspection.proposedRecordID
  }
}

struct PetInstallOutput: Encodable {
  let ok = true
  let changed: Bool
  let recordID: String
  let alreadyInstalled: Bool
  let licenseStatus: String
  let warnings: [String]
  let nextCommands: [String]

  init(outcome: PetInstallOutcome, inspection: PetInspection) {
    changed = !outcome.alreadyInstalled
    recordID = outcome.record.recordID
    alreadyInstalled = outcome.alreadyInstalled
    licenseStatus = outcome.record.licenseStatus.rawValue
    warnings = inspection.warnings.map(\.rawValue)
    nextCommands = ["omapet pet select \(outcome.record.recordID)"]
  }
}

struct PetSelectOutput: Encodable {
  let ok = true
  let changed: Bool
  let selection: PetSelectionOutput
}

struct PetRemoveOutput: Encodable {
  let ok = true
  let changed = true
  let recordID: String
  let selectionReset: Bool
}

struct PetErrorOutput: Encodable {
  let status = "error"
  let code: String
  let detail: [String: String]
}
