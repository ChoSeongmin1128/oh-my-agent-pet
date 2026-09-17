import AgentPetLibrary
import AgentPetSprites
import AppKit
import Combine

@MainActor
public final class PetLibraryViewModel: ObservableObject {
  public struct Row: Identifiable, Equatable {
    public let id: String
    public let selection: PetSelection
    public let title: String
    public let subtitle: String
    public let licenseStatus: PetLicenseStatus?
    public let record: PetLibraryRecord?
    public let issue: PetLibraryEntryIssue?
  }

  public struct Review: Equatable {
    public let staged: PetStagedPackage
    public var inspection: PetInspection { staged.inspection }

    public static func == (lhs: Review, rhs: Review) -> Bool {
      lhs.staged.packageDirectory == rhs.staged.packageDirectory
    }
  }

  @Published public private(set) var rows: [Row] = []
  @Published public private(set) var selection: PetSelection = .original
  @Published public private(set) var selectionIssue: PetSelectionIssue?
  @Published public private(set) var previewPackage: PetSpritePackage?
  @Published public private(set) var thumbnails: [String: NSImage] = [:]
  @Published public private(set) var review: Review?
  @Published public private(set) var isBusy = false
  @Published public var errorMessage: String?
  @Published public var infoRecord: PetLibraryRecord?

  public let service: PetLibraryService
  private let libraryDidChange: @MainActor () -> Void
  private var thumbnailFingerprints: [String: String] = [:]

  public init(service: PetLibraryService, libraryDidChange: @escaping @MainActor () -> Void) {
    self.service = service
    self.libraryDidChange = libraryDidChange
  }

  public func refresh() async {
    let service = self.service
    let snapshot = await Task.detached(priority: .userInitiated) {
      LibrarySnapshot(
        entries: service.entries(),
        resolution: service.resolveSelection()
      )
    }.value
    apply(snapshot)
    await loadThumbnails(for: snapshot.entries)
  }

  public func stage(_ source: PetPackageSource) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    if let review { service.discard(review.staged) }
    review = nil
    let service = self.service
    do {
      let staged = try await Task.detached(priority: .userInitiated) {
        try service.stage(source)
      }.value
      review = Review(staged: staged)
    } catch {
      errorMessage = PetLibraryErrorText.message(for: error)
    }
  }

  public func cancelReview() {
    if let review { service.discard(review.staged) }
    review = nil
  }

  public func installReviewedPackage(useNow: Bool) async {
    guard let review, !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    let service = self.service
    let staged = review.staged
    do {
      let outcome = try await Task.detached(priority: .userInitiated) {
        try service.install(staged)
      }.value
      self.review = nil
      if useNow {
        _ = try service.select(.installed(recordID: outcome.record.recordID))
      }
      libraryDidChange()
      await refresh()
    } catch {
      self.review = nil
      errorMessage = PetLibraryErrorText.message(for: error)
      await refresh()
    }
  }

  public func select(_ selection: PetSelection) async {
    do {
      if try service.select(selection) {
        libraryDidChange()
      }
    } catch {
      errorMessage = PetLibraryErrorText.message(for: error)
    }
    await refresh()
  }

  public func remove(recordID: String) async {
    do {
      _ = try service.remove(recordID: recordID)
      libraryDidChange()
    } catch {
      errorMessage = PetLibraryErrorText.message(for: error)
    }
    await refresh()
  }

  public func revealInFinder(recordID: String) {
    NSWorkspace.shared.activateFileViewerSelecting([service.paths.packageDirectory(for: recordID)])
  }

  public func windowDidClose() {
    cancelReview()
    infoRecord = nil
    errorMessage = nil
  }

  private func apply(_ snapshot: LibrarySnapshot) {
    selection = snapshot.resolution.selection
    selectionIssue = snapshot.resolution.issue
    previewPackage = snapshot.resolution.package
    var rows = [
      Row(
        id: PetSelection.originalIdentifier,
        selection: .original,
        title: "Original vector pet",
        subtitle: "Included with Oh My Agent Pet",
        licenseStatus: nil,
        record: nil,
        issue: nil
      )
    ]
    rows += snapshot.entries.map { entry in
      Row(
        id: entry.recordID,
        selection: .installed(recordID: entry.recordID),
        title: entry.record?.displayName ?? entry.recordID,
        subtitle: entry.record.map(Self.sourceText) ?? "Record unreadable",
        licenseStatus: entry.record?.licenseStatus,
        record: entry.record,
        issue: entry.issue
      )
    }
    rows.append(
      Row(
        id: PetSelection.noneIdentifier,
        selection: .none,
        title: "No pet",
        subtitle: "Show task cards only",
        licenseStatus: nil,
        record: nil,
        issue: nil
      )
    )
    self.rows = rows
  }

  private func loadThumbnails(for entries: [PetLibraryEntry]) async {
    let wanted = entries.compactMap { entry -> (String, String, URL)? in
      guard let record = entry.record, entry.issue == nil else { return nil }
      return (entry.recordID, record.packageFingerprint, entry.packageDirectory)
    }
    thumbnails = thumbnails.filter { key, _ in wanted.contains { $0.0 == key } }
    thumbnailFingerprints = thumbnailFingerprints.filter { key, _ in wanted.contains { $0.0 == key }
    }
    for (recordID, fingerprint, directory) in wanted
    where thumbnailFingerprints[recordID] != fingerprint {
      let package = await Task.detached(priority: .utility) {
        try? PetSpritePackageLoader().load(packageDirectory: directory)
      }.value
      guard let frame = package?.frame(row: 0, column: 0) else { continue }
      thumbnails[recordID] = NSImage(
        cgImage: frame,
        size: NSSize(
          width: DesignTokens.settingsThumbnailSize, height: DesignTokens.settingsThumbnailSize)
      )
      thumbnailFingerprints[recordID] = fingerprint
    }
  }

  static func sourceText(_ record: PetLibraryRecord) -> String {
    switch record.source {
    case .folder(let name): "Folder: \(name)"
    case .archive(let fileName): "Archive: \(fileName)"
    case .url(let url): url.host ?? url.absoluteString
    }
  }
}

private struct LibrarySnapshot: Sendable {
  let entries: [PetLibraryEntry]
  let resolution: PetSelectionResolution
}

enum PetLibraryErrorText {
  static func message(for error: Error) -> String {
    guard let error = error as? PetLibraryError else {
      return "The pet could not be processed."
    }
    switch error.code {
    case .sourceUnavailable: return "The selected folder or file could not be found."
    case .unsupportedSource:
      return "Choose a package folder with pet.json, a codex-pet ZIP, or a codex-pets.net link."
    case .invalidManifest: return "pet.json could not be read."
    case .unsupportedVersion: return "This pet declares an unsupported sprite version."
    case .versionDimensionMismatch:
      return "The spritesheet size does not match the declared sprite version."
    case .missingRequiredFrame: return "A required animation frame is empty."
    case .damagedImage: return "The spritesheet image could not be decoded."
    case .unsafePackage: return "The package contains files that are not allowed."
    case .oversizedPackage: return "The package is larger than the allowed size."
    case .writeFailed: return "The pet library could not be written."
    case .urlNotAllowed: return "Only HTTPS links to codex-pets.net are supported."
    case .redirectLimitExceeded: return "The download was redirected too many times."
    case .downloadFailed: return "The download did not complete."
    case .petNotFound: return "codex-pets.net has no pet with that name."
    case .invalidGalleryResponse: return "codex-pets.net returned an unexpected response."
    case .invalidRecordID: return "The pet identifier is not valid."
    case .recordNotFound: return "That pet is not in the library."
    case .selectionStoreUnsupported: return "The pet selection was saved by a newer version."
    }
  }

  static func licenseLabel(_ status: PetLicenseStatus?) -> (text: String, tone: StatusChipTone) {
    switch status {
    case .bundledVerified?: ("License verified", .positive)
    case .externallyDeclared?: ("License declared", .info)
    case .unknown?: ("No license info", .warning)
    case nil: ("Built in", .neutral)
    }
  }

  static func issueText(_ issue: PetSelectionIssue) -> String {
    switch issue {
    case .recordMissing(let recordID):
      "The selected pet \"\(recordID)\" is no longer in the library. The original pet is shown instead."
    case .packageDamaged(let recordID, _):
      "The selected pet \"\(recordID)\" could not be loaded. The original pet is shown instead."
    case .selectionFileCorrupt:
      "The saved pet selection could not be read. The original pet is shown."
    case .selectionSchemaUnsupported:
      "The saved pet selection was written by a newer version. The original pet is shown."
    }
  }
}
