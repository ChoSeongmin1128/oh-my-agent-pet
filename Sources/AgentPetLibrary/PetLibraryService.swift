import AgentPetSprites
import Foundation

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
  private var stager: PetPackageStager { PetPackageStager(fileSystem: fileSystem) }

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
      try stager.createDirectory(packageDirectory)
      let installSource: PetInstallSource
      let attribution: String?
      switch source {
      case .folder(let directory):
        try stager.copyFolderPackage(from: directory, to: packageDirectory)
        installSource = .folder(name: directory.lastPathComponent)
        attribution = nil
      case .archive(let file):
        try stager.extractArchive(try stager.readArchiveFile(file), to: packageDirectory)
        installSource = .archive(fileName: file.lastPathComponent)
        attribution = nil
      case .url(let url):
        guard let reference = PetGalleryURLParser.parse(url) else {
          throw PetLibraryError(.urlNotAllowed, detail: ["host": url.host ?? ""])
        }
        let client = PetGalleryClient(downloader: downloader)
        let download = try client.resolveDownload(reference)
        try stager.extractArchive(try client.downloadArchive(download), to: packageDirectory)
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
    guard PetRecordIDPolicy.isValid(recordID) else {
      throw PetLibraryError(.invalidRecordID)
    }
    guard fileSystem.itemType(at: paths.recordFile(for: recordID)) == .regularFile else {
      return nil
    }
    return try readRecord(recordID: recordID)
  }

  public func remove(recordID: String) throws -> PetRemoveOutcome {
    guard PetRecordIDPolicy.isValid(recordID) else {
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
    let selectionReset = loadSelection().selection == .installed(recordID: recordID)
    if selectionReset {
      do {
        try selectionStore.save(.original)
      } catch {
        do {
          try fileSystem.moveItem(at: trash, to: directory)
        } catch {
          throw PetLibraryError(.writeFailed, detail: ["reason": "remove_rollback"])
        }
        throw error
      }
    }
    try? fileSystem.removeItem(at: trash)
    return PetRemoveOutcome(recordID: recordID, selectionReset: selectionReset)
  }

  public func loadSelection() -> PetSelectionLoad {
    selectionStore.load()
  }

  public func select(_ selection: PetSelection) throws -> Bool {
    if case .installed(let recordID) = selection {
      guard PetRecordIDPolicy.isValid(recordID) else {
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
        ?? PetRecordIDPolicy.propose(
          manifestID: manifestID, fingerprint: packageFingerprint, takenIDs: takenIDs)
    )
    return (inspection, package)
  }

}
