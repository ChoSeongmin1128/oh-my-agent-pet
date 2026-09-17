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

public struct PetLibraryService: Sendable {
  public let paths: PetLibraryPaths
  private let fileSystem: PetLibraryFileSystem
  private let downloader: PetPackageDownloader
  private let now: @Sendable () -> Date
  private let makeStageIdentifier: @Sendable () -> String
  private var selectionStore: PetSelectionStore {
    PetSelectionStore(url: paths.selectionURL, fileSystem: fileSystem)
  }
  private var loader: PetSpritePackageLoader { PetSpritePackageLoader() }

  public init(
    paths: PetLibraryPaths,
    fileSystem: PetLibraryFileSystem = DefaultPetLibraryFileSystem(),
    downloader: PetPackageDownloader = URLSessionPetPackageDownloader(),
    now: @escaping @Sendable () -> Date = Date.init,
    makeStageIdentifier: @escaping @Sendable () -> String = { UUID().uuidString }
  ) {
    self.paths = paths
    self.fileSystem = fileSystem
    self.downloader = downloader
    self.now = now
    self.makeStageIdentifier = makeStageIdentifier
  }

  // Creates the library layout and drops stage directories left by an interrupted install.
  // Only the app calls this at launch; a one-shot CLI process cleans its own stage instead.
  public func prepare() throws {
    do {
      try fileSystem.createDirectory(at: paths.libraryDirectory)
      try fileSystem.createDirectory(at: paths.stagingDirectory)
      for leftover in try fileSystem.contentsOfDirectory(at: paths.stagingDirectory) {
        try fileSystem.removeItem(at: leftover)
      }
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "prepare"])
    }
  }

  public func stage(_ source: PetPackageSource) throws -> PetStagedPackage {
    let stageDirectory = paths.stagingDirectory.appendingPathComponent(
      makeStageIdentifier(), isDirectory: true)
    let packageDirectory = stageDirectory.appendingPathComponent(
      PetLibraryPaths.packageDirectoryName, isDirectory: true)
    do {
      try createDirectory(packageDirectory)
      let installSource: PetInstallSource
      let attribution: String?
      switch source {
      case .folder(let directory):
        try copyFolderPackage(from: directory, to: packageDirectory)
        installSource = .folder(name: directory.lastPathComponent)
        attribution = nil
      case .archive(let file):
        try extractArchive(try readArchiveFile(file), to: packageDirectory)
        installSource = .archive(fileName: file.lastPathComponent)
        attribution = nil
      case .url(let url):
        guard let reference = PetGalleryURLParser.parse(url) else {
          throw PetLibraryError(.urlNotAllowed, detail: ["host": url.host ?? ""])
        }
        let client = PetGalleryClient(downloader: downloader)
        let download = try client.resolveDownload(reference)
        try extractArchive(try client.downloadArchive(download), to: packageDirectory)
        installSource = .url(reference.pageURL)
        attribution = download.ownerHandle
      }
      let (inspection, package) = try inspectStaged(
        packageDirectory, source: installSource, attribution: attribution)
      return PetStagedPackage(
        stageDirectory: stageDirectory,
        packageDirectory: packageDirectory,
        inspection: inspection,
        package: package
      )
    } catch {
      try? fileSystem.removeItem(at: stageDirectory)
      throw error
    }
  }

  public func discard(_ staged: PetStagedPackage) {
    try? fileSystem.removeItem(at: staged.stageDirectory)
  }

  public func install(_ staged: PetStagedPackage) throws -> PetInstallOutcome {
    if let duplicateOf = staged.inspection.duplicateOf, let existing = try record(for: duplicateOf)
    {
      discard(staged)
      return PetInstallOutcome(record: existing, alreadyInstalled: true)
    }
    let inspection = staged.inspection
    let record = PetLibraryRecord(
      recordID: inspection.proposedRecordID,
      manifestID: inspection.manifestID,
      displayName: inspection.displayName,
      description: inspection.description,
      spriteVersion: inspection.spriteVersion,
      spritesheetPath: inspection.spritesheetPath,
      installedAt: now(),
      source: inspection.source,
      packageFingerprint: inspection.packageFingerprint,
      spritesheetFingerprint: inspection.spritesheetFingerprint,
      license: inspection.license,
      licenseStatus: inspection.licenseStatus
    )
    let destination = paths.recordDirectory(for: record.recordID)
    do {
      let recordFile = staged.stageDirectory.appendingPathComponent(
        PetLibraryPaths.recordFileName, isDirectory: false)
      try fileSystem.writeData(try PetLibraryRecord.makeEncoder().encode(record), to: recordFile)
      try fileSystem.createDirectory(at: paths.libraryDirectory)
      guard fileSystem.itemType(at: destination) == .missing else {
        throw PetLibraryError(.writeFailed, detail: ["reason": "destination_exists"])
      }
      try fileSystem.moveItem(at: staged.stageDirectory, to: destination)
    } catch let error as PetLibraryError {
      discard(staged)
      throw error
    } catch {
      discard(staged)
      throw PetLibraryError(.writeFailed, detail: ["reason": "commit"])
    }
    return PetInstallOutcome(record: record, alreadyInstalled: false)
  }

  public func entries() -> [PetLibraryEntry] {
    guard fileSystem.itemType(at: paths.libraryDirectory) == .directory,
      let items = try? fileSystem.contentsOfDirectory(at: paths.libraryDirectory)
    else {
      return []
    }
    let entries = items.compactMap { item -> PetLibraryEntry? in
      let recordID = item.lastPathComponent
      guard !recordID.hasPrefix("."), fileSystem.itemType(at: item) == .directory else {
        return nil
      }
      let packageDirectory = paths.packageDirectory(for: recordID)
      guard let record = try? readRecord(recordID: recordID) else {
        return PetLibraryEntry(
          recordID: recordID, record: nil, issue: .recordUnreadable,
          packageDirectory: packageDirectory)
      }
      let manifestURL = packageDirectory.appendingPathComponent("pet.json", isDirectory: false)
      let spritesheetURL = packageDirectory.appendingPathComponent(
        record.spritesheetPath, isDirectory: false)
      let filesPresent =
        fileSystem.itemType(at: manifestURL) == .regularFile
        && fileSystem.itemType(at: spritesheetURL) == .regularFile
      return PetLibraryEntry(
        recordID: recordID,
        record: record,
        issue: filesPresent ? nil : .packageFilesMissing,
        packageDirectory: packageDirectory
      )
    }
    return entries.sorted {
      ($0.record?.installedAt ?? .distantPast, $0.recordID)
        < ($1.record?.installedAt ?? .distantPast, $1.recordID)
    }
  }

  public func record(for recordID: String) throws -> PetLibraryRecord? {
    guard PetRecordIdentifier.isValid(recordID) else {
      throw PetLibraryError(.invalidRecordID)
    }
    guard fileSystem.itemType(at: paths.recordFile(for: recordID)) == .regularFile else {
      return nil
    }
    return try readRecord(recordID: recordID)
  }

  public func remove(recordID: String) throws -> PetRemoveOutcome {
    guard PetRecordIdentifier.isValid(recordID) else {
      throw PetLibraryError(.invalidRecordID)
    }
    let directory = paths.recordDirectory(for: recordID)
    guard fileSystem.itemType(at: directory) == .directory else {
      throw PetLibraryError(.recordNotFound, detail: ["recordID": recordID])
    }
    let trash = paths.stagingDirectory.appendingPathComponent(
      "\(makeStageIdentifier())-remove", isDirectory: true)
    do {
      try fileSystem.createDirectory(at: paths.stagingDirectory)
      try fileSystem.moveItem(at: directory, to: trash)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "remove"])
    }
    try? fileSystem.removeItem(at: trash)
    var selectionReset = false
    if loadSelection().selection == .installed(recordID: recordID) {
      try selectionStore.save(.original)
      selectionReset = true
    }
    return PetRemoveOutcome(recordID: recordID, selectionReset: selectionReset)
  }

  public func loadSelection() -> PetSelectionLoad {
    selectionStore.load()
  }

  public func select(_ selection: PetSelection) throws -> Bool {
    if case .installed(let recordID) = selection {
      guard PetRecordIdentifier.isValid(recordID) else {
        throw PetLibraryError(.invalidRecordID)
      }
      guard fileSystem.itemType(at: paths.recordDirectory(for: recordID)) == .directory else {
        throw PetLibraryError(.recordNotFound, detail: ["recordID": recordID])
      }
    }
    let current = selectionStore.load()
    if current.issue == nil, current.selection == selection {
      return false
    }
    try selectionStore.save(selection)
    return true
  }

  public func resolveSelection() -> PetSelectionResolution {
    let load = selectionStore.load()
    let storeIssue: PetSelectionIssue? =
      switch load.issue {
      case .corruptFile?: .selectionFileCorrupt
      case .unsupportedSchema(let version)?: .selectionSchemaUnsupported(version)
      case nil: nil
      }
    guard case .installed(let recordID) = load.selection else {
      return PetSelectionResolution(
        selection: load.selection, record: nil, package: nil, issue: storeIssue)
    }
    guard let record = try? record(for: recordID) else {
      return PetSelectionResolution(
        selection: load.selection, record: nil, package: nil,
        issue: .recordMissing(recordID: recordID))
    }
    do {
      let package = try loader.load(packageDirectory: paths.packageDirectory(for: recordID))
      return PetSelectionResolution(
        selection: load.selection, record: record, package: package, issue: nil)
    } catch let error as PetSpritePackageError {
      return PetSelectionResolution(
        selection: load.selection, record: record, package: nil,
        issue: .packageDamaged(recordID: recordID, code: PetLibraryError(spriteError: error).code))
    } catch {
      return PetSelectionResolution(
        selection: load.selection, record: record, package: nil,
        issue: .packageDamaged(recordID: recordID, code: .damagedImage))
    }
  }

  private func readRecord(recordID: String) throws -> PetLibraryRecord {
    let data = try fileSystem.readData(
      at: paths.recordFile(for: recordID),
      maximumBytes: PetSpritePackageLoader.maximumManifestBytes
    )
    let record = try PetLibraryRecord.makeDecoder().decode(PetLibraryRecord.self, from: data)
    guard record.recordID == recordID,
      record.schemaVersion == PetLibraryPolicy.recordSchemaVersion
    else {
      throw PetLibraryError(.recordNotFound, detail: ["recordID": recordID])
    }
    return record
  }

  private func createDirectory(_ url: URL) throws {
    do {
      try fileSystem.createDirectory(at: url)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "create_directory"])
    }
  }

  private func copyFolderPackage(from sourceDirectory: URL, to packageDirectory: URL) throws {
    switch fileSystem.itemType(at: sourceDirectory) {
    case .directory:
      break
    case .missing:
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "missing"])
    case .regularFile, .symbolicLink, .other:
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_directory"])
    }
    let manifestName = "pet.json"
    try copyRegularFile(
      at: sourceDirectory.appendingPathComponent(manifestName, isDirectory: false),
      to: packageDirectory.appendingPathComponent(manifestName, isDirectory: false),
      limit: PetSpritePackageLoader.maximumManifestBytes,
      missingReason: "missing_manifest"
    )
    let manifestData = try fileSystem.readData(
      at: packageDirectory.appendingPathComponent(manifestName, isDirectory: false),
      maximumBytes: PetSpritePackageLoader.maximumManifestBytes
    )
    guard let manifest = try? JSONDecoder().decode(PetSpriteManifest.self, from: manifestData)
    else {
      throw PetLibraryError(.invalidManifest, detail: ["reason": "undecodable"])
    }
    guard PetSpritePackageLoader.isSafeRelativePath(manifest.spritesheetPath) else {
      throw PetLibraryError(.unsafePackage, detail: ["reason": "unsafe_spritesheet_path"])
    }
    try copyRegularFile(
      at: sourceDirectory.appendingPathComponent(manifest.spritesheetPath, isDirectory: false),
      to: packageDirectory.appendingPathComponent(manifest.spritesheetPath, isDirectory: false),
      limit: PetSpritePackageLoader.maximumSpritesheetBytes,
      missingReason: "missing_spritesheet"
    )

    let siblings: [URL]
    do {
      siblings = try fileSystem.contentsOfDirectory(at: sourceDirectory)
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_directory"])
    }
    var auxiliaryBytes = 0
    for item in siblings.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let name = item.lastPathComponent
      guard !name.hasPrefix("."), name != manifestName, name != manifest.spritesheetPath else {
        continue
      }
      switch fileSystem.itemType(at: item) {
      case .regularFile:
        let size = try fileSize(at: item)
        auxiliaryBytes += size
        guard auxiliaryBytes <= PetLibraryPolicy.auxiliaryFilesAllowanceBytes else {
          throw PetLibraryError(.oversizedPackage, detail: ["reason": "auxiliary_files_too_large"])
        }
        try copyRegularFile(
          at: item,
          to: packageDirectory.appendingPathComponent(name, isDirectory: false),
          limit: PetLibraryPolicy.auxiliaryFilesAllowanceBytes,
          missingReason: "missing_file"
        )
      case .symbolicLink:
        throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
      case .directory, .missing, .other:
        continue
      }
    }
  }

  private func copyRegularFile(
    at source: URL,
    to destination: URL,
    limit: Int,
    missingReason: String
  ) throws {
    switch fileSystem.itemType(at: source) {
    case .regularFile:
      break
    case .missing:
      throw PetLibraryError(.unsafePackage, detail: ["reason": missingReason])
    case .symbolicLink:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
    case .directory, .other:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "not_regular_file"])
    }
    guard try fileSize(at: source) <= limit else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "file_too_large"])
    }
    try createDirectory(destination.deletingLastPathComponent())
    do {
      try fileSystem.copyFile(at: source, to: destination)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "copy"])
    }
  }

  private func fileSize(at url: URL) throws -> Int {
    do {
      return try fileSystem.fileSize(at: url)
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_file"])
    }
  }

  private func readArchiveFile(_ file: URL) throws -> Data {
    switch fileSystem.itemType(at: file) {
    case .regularFile:
      break
    case .missing:
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "missing"])
    case .symbolicLink:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
    case .directory, .other:
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_package"])
    }
    guard try fileSize(at: file) <= PetLibraryPolicy.maximumArchiveBytes else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "archive_too_large"])
    }
    do {
      return try fileSystem.readData(at: file, maximumBytes: PetLibraryPolicy.maximumArchiveBytes)
    } catch let error as PetLibraryError {
      throw error
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_file"])
    }
  }

  private func extractArchive(_ data: Data, to packageDirectory: URL) throws {
    let reader: ZipArchiveReader
    do {
      reader = try ZipArchiveReader(data: data)
    } catch ZipArchiveError.unsupportedFeature(let feature) {
      throw PetLibraryError(
        .unsafePackage, detail: ["reason": "unsupported_zip_feature", "feature": feature])
    } catch {
      throw PetLibraryError(.unsafePackage, detail: ["reason": "not_a_zip_archive"])
    }
    guard reader.entries.count <= PetLibraryPolicy.maximumArchiveEntries else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "too_many_entries"])
    }

    var files: [ZipArchiveEntry] = []
    var seenNames = Set<String>()
    var unpackedBytes = 0
    for entry in reader.entries {
      guard !entry.isEncrypted else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "encrypted_entry"])
      }
      guard !entry.isSymbolicLink else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
      }
      let name =
        entry.isDirectory && entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name
      guard PetSpritePackageLoader.isSafeRelativePath(name) else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "unsafe_entry_path"])
      }
      guard !entry.isDirectory else { continue }
      let components = name.split(separator: "/").map(String.init)
      guard components.first != PetLibraryPolicy.ignoredArchiveDirectory,
        components.last?.hasPrefix(".") == false
      else {
        continue
      }
      guard seenNames.insert(name.lowercased()).inserted else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "duplicate_entry"])
      }
      guard entry.uncompressedSize <= PetSpritePackageLoader.maximumSpritesheetBytes else {
        throw PetLibraryError(.oversizedPackage, detail: ["reason": "entry_too_large"])
      }
      unpackedBytes += entry.uncompressedSize
      guard unpackedBytes <= PetLibraryPolicy.maximumUnpackedBytes else {
        throw PetLibraryError(.oversizedPackage, detail: ["reason": "unpacked_too_large"])
      }
      files.append(entry)
    }

    let root: String
    if files.contains(where: { $0.name == "pet.json" }) {
      root = ""
    } else {
      let firstComponents = Set(
        files.compactMap { $0.name.split(separator: "/").first.map(String.init) })
      guard firstComponents.count == 1, let only = firstComponents.first,
        files.contains(where: { $0.name == "\(only)/pet.json" })
      else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "package_root"])
      }
      root = only + "/"
    }

    for entry in files {
      let relativePath = String(entry.name.dropFirst(root.count))
      let destination = packageDirectory.appendingPathComponent(relativePath, isDirectory: false)
      let contents: Data
      do {
        contents = try reader.extract(entry)
      } catch ZipArchiveError.unsupportedFeature(let feature) {
        throw PetLibraryError(
          .unsafePackage, detail: ["reason": "unsupported_zip_feature", "feature": feature])
      } catch {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "corrupt_entry"])
      }
      try createDirectory(destination.deletingLastPathComponent())
      do {
        try fileSystem.writeData(contents, to: destination)
      } catch {
        throw PetLibraryError(.writeFailed, detail: ["reason": "extract"])
      }
    }
  }

  private func inspectStaged(
    _ packageDirectory: URL,
    source: PetInstallSource,
    attribution: String?
  ) throws -> (PetInspection, PetSpritePackage) {
    let package: PetSpritePackage
    do {
      package = try loader.load(packageDirectory: packageDirectory)
    } catch let error as PetSpritePackageError {
      throw PetLibraryError(spriteError: error)
    }
    let manifestData = try fileSystem.readData(
      at: packageDirectory.appendingPathComponent("pet.json", isDirectory: false),
      maximumBytes: PetSpritePackageLoader.maximumManifestBytes
    )
    let spritesheetData = try fileSystem.readData(
      at: packageDirectory.appendingPathComponent(
        package.manifest.spritesheetPath, isDirectory: false),
      maximumBytes: PetSpritePackageLoader.maximumSpritesheetBytes
    )
    let spritesheetFingerprint = PetPackageFingerprint.spritesheetDigest(spritesheetData)
    let packageFingerprint: String
    do {
      packageFingerprint = try PetPackageFingerprint.packageDigest(
        manifest: manifestData, spritesheetDigest: spritesheetFingerprint)
    } catch {
      throw PetLibraryError(.invalidManifest, detail: ["reason": "not_canonicalizable"])
    }
    let rootFileNames = ((try? fileSystem.contentsOfDirectory(at: packageDirectory)) ?? [])
      .filter { fileSystem.itemType(at: $0) == .regularFile }
      .map(\.lastPathComponent)
    let license = PetLicenseReader.declaration(
      manifest: manifestData, rootFileNames: rootFileNames, fallbackAttribution: attribution)
    let licenseStatus = PetLicenseReader.status(for: license)

    let existing = entries()
    let duplicate = existing.first { $0.record?.packageFingerprint == packageFingerprint }
    let takenIDs = Set(existing.map(\.recordID))
    let manifestID = package.manifest.id
    var warnings: [PetInspectionWarning] = []
    if licenseStatus == .unknown { warnings.append(.licenseUnknown) }
    if duplicate != nil {
      warnings.append(.duplicateAsset)
    } else if existing.contains(where: { $0.record?.manifestID == manifestID }) {
      warnings.append(.manifestIDInUse)
    }
    let inspection = PetInspection(
      manifestID: manifestID,
      displayName: package.manifest.displayName,
      description: package.manifest.description,
      spriteVersion: package.version.rawValue,
      spritesheetPath: package.manifest.spritesheetPath,
      source: source,
      packageFingerprint: packageFingerprint,
      spritesheetFingerprint: spritesheetFingerprint,
      license: license,
      licenseStatus: licenseStatus,
      warnings: warnings,
      duplicateOf: duplicate?.recordID,
      proposedRecordID: duplicate?.recordID
        ?? Self.proposeRecordID(
          manifestID: manifestID, fingerprint: packageFingerprint, takenIDs: takenIDs)
    )
    return (inspection, package)
  }

  static func proposeRecordID(manifestID: String, fingerprint: String, takenIDs: Set<String>)
    -> String
  {
    if !PetSelection.reservedIdentifiers.contains(manifestID), !takenIDs.contains(manifestID) {
      return manifestID
    }
    var length = PetLibraryPolicy.recordIdentifierSuffixLength
    while length <= fingerprint.count {
      let candidate = "\(manifestID)-\(fingerprint.prefix(length))"
      if !takenIDs.contains(candidate) { return candidate }
      length += PetLibraryPolicy.recordIdentifierSuffixLength
    }
    return "\(manifestID)-\(fingerprint)"
  }
}
