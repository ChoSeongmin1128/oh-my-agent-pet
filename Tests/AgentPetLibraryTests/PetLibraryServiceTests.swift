import AgentPetLibrary
import AgentPetSprites
import AgentPetTestSupport
import Foundation
import XCTest

final class PetLibraryServiceTests: XCTestCase {
  private var fixture: LibraryFixture!

  override func setUpWithError() throws {
    fixture = try LibraryFixture()
  }

  override func tearDown() {
    fixture.remove()
    fixture = nil
  }

  func testFolderInstallCopiesPackageLeavesSourceUntouchedAndListsOnce() throws {
    let source = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("haaap"), id: "haaap", displayName: "Haaap", version: 1)
    let before = try directorySnapshot(source)

    let staged = try fixture.service.stage(.folder(source))
    XCTAssertEqual(staged.inspection.manifestID, "haaap")
    XCTAssertEqual(staged.inspection.spriteVersion, 1)
    XCTAssertEqual(staged.inspection.proposedRecordID, "haaap")
    XCTAssertEqual(staged.inspection.licenseStatus, .unknown)
    XCTAssertEqual(staged.inspection.warnings, [.licenseUnknown])
    XCTAssertNil(staged.inspection.duplicateOf)
    XCTAssertEqual(fixture.service.entries().count, 0, "staging must not appear in the library")

    let outcome = try fixture.service.install(staged)
    XCTAssertFalse(outcome.alreadyInstalled)
    XCTAssertEqual(outcome.record.recordID, "haaap")
    XCTAssertEqual(outcome.record.source, .folder(name: "haaap"))
    XCTAssertEqual(outcome.record.installedAt, fixture.installedAt)

    let entries = fixture.service.entries()
    XCTAssertEqual(entries.map(\.recordID), ["haaap"])
    XCTAssertNil(entries[0].issue)
    XCTAssertEqual(entries[0].record, outcome.record)
    XCTAssertEqual(try directorySnapshot(source), before)
    XCTAssertEqual(
      try directorySnapshot(fixture.paths.packageDirectory(for: "haaap")),
      before,
      "library copy is byte-for-byte identical"
    )
    XCTAssertTrue(
      (try FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path))
        .isEmpty
    )
    let loaded = try PetSpritePackageLoader().load(
      packageDirectory: fixture.paths.packageDirectory(for: "haaap"))
    XCTAssertEqual(loaded.manifest.id, "haaap")
  }

  func testV2InstallAndSpritesheetInSubdirectory() throws {
    let source = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("mochi"), id: "mochi", version: 2,
      spritesheetPath: "sprites/sheet.png")

    let outcome = try fixture.service.install(try fixture.service.stage(.folder(source)))

    XCTAssertEqual(outcome.record.spriteVersion, 2)
    XCTAssertEqual(outcome.record.spritesheetPath, "sprites/sheet.png")
    XCTAssertEqual(fixture.service.entries().first?.issue, nil)
  }

  func testInvalidPackagesReportTypedCodesAndLeaveNoStage() throws {
    let cases: [(String, (URL) throws -> Void, PetLibraryError.Code)] = [
      (
        "unsupported-version",
        { try PetPackageFixture.writePackage(into: $0, version: 3) },
        .unsupportedVersion
      ),
      (
        "dimension-mismatch",
        { try PetPackageFixture.writePackage(into: $0, version: 1, rows: 11) },
        .versionDimensionMismatch
      ),
      (
        "empty-frame",
        { try PetPackageFixture.writePackage(into: $0, emptyFrame: (row: 5, column: 7)) },
        .missingRequiredFrame
      ),
      (
        "invalid-manifest",
        { directory in
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try Data("{broken".utf8).write(to: directory.appendingPathComponent("pet.json"))
        },
        .invalidManifest
      ),
      (
        "missing-manifest",
        { directory in
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        },
        .unsafePackage
      ),
      (
        "damaged-image",
        { directory in
          try PetPackageFixture.writePackage(into: directory)
          try Data("not an image".utf8).write(
            to: directory.appendingPathComponent("spritesheet.png"))
        },
        .damagedImage
      ),
    ]
    for (name, build, code) in cases {
      let directory = fixture.sourceDirectory(name)
      try build(directory)
      assertLibraryError(try fixture.service.stage(.folder(directory)), code)
    }
    assertLibraryError(
      try fixture.service.stage(.folder(fixture.sourceDirectory("does-not-exist"))),
      .sourceUnavailable
    )
    XCTAssertEqual(fixture.service.entries(), [])
    XCTAssertEqual(
      (try? FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path))
        ?? [],
      []
    )
  }

  func testSymlinkInsideSourceFolderIsRejected() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("linked"))
    try FileManager.default.createSymbolicLink(
      at: source.appendingPathComponent("LICENSE"),
      withDestinationURL: URL(fileURLWithPath: "/etc/hosts")
    )

    assertLibraryError(
      try fixture.service.stage(.folder(source)), .unsafePackage, reason: "symbolic_link")
  }

  func testOversizedManifestIsRejectedBeforeCopy() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("big"))
    let handle = try FileHandle(forWritingTo: source.appendingPathComponent("pet.json"))
    try handle.truncate(atOffset: UInt64(PetSpritePackageLoader.maximumManifestBytes + 1))
    try handle.close()

    assertLibraryError(try fixture.service.stage(.folder(source)), .oversizedPackage)
  }

  func testDuplicateFingerprintReusesExistingRecord() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("dup"), id: "dup")
    let first = try fixture.service.install(try fixture.service.stage(.folder(source)))

    let reformatted = fixture.sourceDirectory("dup-reformatted")
    try FileManager.default.copyItem(at: source, to: reformatted)
    let object =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: reformatted.appendingPathComponent("pet.json"))) as! [String: Any]
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
      .write(to: reformatted.appendingPathComponent("pet.json"))

    let staged = try fixture.service.stage(.folder(reformatted))
    XCTAssertEqual(staged.inspection.duplicateOf, "dup")
    XCTAssertEqual(staged.inspection.proposedRecordID, "dup")
    XCTAssertEqual(staged.inspection.warnings, [.licenseUnknown, .duplicateAsset])
    XCTAssertEqual(staged.inspection.packageFingerprint, first.record.packageFingerprint)

    let outcome = try fixture.service.install(staged)
    XCTAssertTrue(outcome.alreadyInstalled)
    XCTAssertEqual(outcome.record, first.record)
    XCTAssertEqual(fixture.service.entries().count, 1)
  }

  func testSameManifestIDWithDifferentAssetGetsSuffixedRecordID() throws {
    let first = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("a"), id: "twin", seed: 1)
    let second = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("b"), id: "twin", seed: 200)
    _ = try fixture.service.install(try fixture.service.stage(.folder(first)))
    fixture.advanceClock()

    let staged = try fixture.service.stage(.folder(second))
    XCTAssertNil(staged.inspection.duplicateOf)
    XCTAssertTrue(staged.inspection.warnings.contains(.manifestIDInUse))
    XCTAssertEqual(
      staged.inspection.proposedRecordID,
      "twin-\(staged.inspection.packageFingerprint.prefix(8))"
    )
    let outcome = try fixture.service.install(staged)
    XCTAssertEqual(fixture.service.entries().map(\.recordID), ["twin", outcome.record.recordID])
    XCTAssertNotEqual(
      fixture.service.entries()[0].record?.packageFingerprint,
      fixture.service.entries()[1].record?.packageFingerprint
    )
  }

  func testReservedManifestIDsNeverBecomeBareRecordIDs() throws {
    for reserved in ["original", "none"] {
      let source = try PetPackageFixture.writePackage(
        into: fixture.sourceDirectory(reserved), id: reserved)
      let staged = try fixture.service.stage(.folder(source))
      XCTAssertTrue(staged.inspection.proposedRecordID.hasPrefix("\(reserved)-"))
      fixture.service.discard(staged)
    }
  }

  func testSelectionRoundTripAndRemovalResetsSelection() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("sel"), id: "sel")
    let record = try fixture.service.install(try fixture.service.stage(.folder(source))).record

    XCTAssertEqual(fixture.service.loadSelection(), PetSelectionLoad(selection: .original))
    XCTAssertTrue(try fixture.service.select(.installed(recordID: record.recordID)))
    XCTAssertFalse(try fixture.service.select(.installed(recordID: record.recordID)))
    XCTAssertEqual(
      fixture.service.loadSelection().selection, .installed(recordID: record.recordID))
    let resolved = fixture.service.resolveSelection()
    XCTAssertNotNil(resolved.package)
    XCTAssertNil(resolved.issue)
    XCTAssertEqual(resolved.record, record)

    XCTAssertTrue(try fixture.service.select(.none))
    XCTAssertEqual(fixture.service.loadSelection().selection, .none)
    XCTAssertNil(fixture.service.resolveSelection().package)
    XCTAssertTrue(try fixture.service.select(.installed(recordID: record.recordID)))

    let outcome = try fixture.service.remove(recordID: record.recordID)
    XCTAssertTrue(outcome.selectionReset)
    XCTAssertEqual(fixture.service.loadSelection().selection, .original)
    XCTAssertEqual(fixture.service.entries(), [])
    XCTAssertEqual(try directorySnapshot(source).count, 2, "source package is preserved")
    assertLibraryError(try fixture.service.remove(recordID: record.recordID), .recordNotFound)
    assertLibraryError(try fixture.service.remove(recordID: "../escape"), .invalidRecordID)
    assertLibraryError(
      try fixture.service.select(.installed(recordID: "missing")), .recordNotFound)
  }

  func testSelectedRemovalRollsBackLibraryWhenSelectionResetFails() throws {
    let source = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("rollback-remove"),
      id: "rollback-remove"
    )
    let record = try fixture.service.install(try fixture.service.stage(.folder(source))).record
    _ = try fixture.service.select(.installed(recordID: record.recordID))
    fixture.fileSystem.fail(.writeData)

    assertLibraryError(
      try fixture.service.remove(recordID: record.recordID),
      .writeFailed
    )

    XCTAssertNotNil(try fixture.service.record(for: record.recordID))
    XCTAssertEqual(
      fixture.service.loadSelection().selection,
      .installed(recordID: record.recordID)
    )
    XCTAssertEqual(fixture.service.entries().map(\.recordID), [record.recordID])
  }

  func testDamagedOrMissingSelectedPackageFallsBackWithIssue() throws {
    let source = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("frag"), id: "frag")
    let record = try fixture.service.install(try fixture.service.stage(.folder(source))).record
    _ = try fixture.service.select(.installed(recordID: record.recordID))

    try Data("broken".utf8).write(
      to: fixture.paths.packageDirectory(for: record.recordID)
        .appendingPathComponent("spritesheet.png"))
    let damaged = fixture.service.resolveSelection()
    XCTAssertNil(damaged.package)
    XCTAssertEqual(damaged.issue, .packageDamaged(recordID: "frag", code: .damagedImage))
    XCTAssertEqual(damaged.selection, .installed(recordID: "frag"))

    try FileManager.default.removeItem(at: fixture.paths.recordDirectory(for: record.recordID))
    let missing = fixture.service.resolveSelection()
    XCTAssertNil(missing.package)
    XCTAssertEqual(missing.issue, .recordMissing(recordID: "frag"))
    XCTAssertEqual(fixture.service.loadSelection().selection, .installed(recordID: "frag"))
  }

  func testEntriesReportUnreadableRecordsAndMissingFiles() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("ok"), id: "ok")
    let record = try fixture.service.install(try fixture.service.stage(.folder(source))).record
    try FileManager.default.removeItem(
      at: fixture.paths.packageDirectory(for: record.recordID)
        .appendingPathComponent("spritesheet.png"))
    let brokenDirectory = fixture.paths.recordDirectory(for: "broken")
    try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: brokenDirectory.appendingPathComponent("record.json"))

    let entries = fixture.service.entries()

    XCTAssertEqual(entries.map(\.recordID), ["broken", "ok"])
    XCTAssertEqual(entries[0].issue, .recordUnreadable)
    XCTAssertNil(entries[0].record)
    XCTAssertEqual(entries[1].issue, .packageFilesMissing)
    XCTAssertEqual(try fixture.service.remove(recordID: "broken").selectionReset, false)
    XCTAssertEqual(fixture.service.entries().map(\.recordID), ["ok"])
  }

  func testCommitFailureKeepsLibraryAndSelectionAndCleansStage() throws {
    let existing = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("keep"), id: "keep", seed: 3)
    let kept = try fixture.service.install(try fixture.service.stage(.folder(existing))).record
    _ = try fixture.service.select(.installed(recordID: kept.recordID))
    let librarySnapshot = try directorySnapshot(fixture.paths.libraryDirectory)

    let incoming = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("incoming"), id: "incoming", seed: 90)
    let staged = try fixture.service.stage(.folder(incoming))
    fixture.fileSystem.fail(.moveItem)

    assertLibraryError(try fixture.service.install(staged), .writeFailed)
    XCTAssertEqual(fixture.service.entries().map(\.recordID), ["keep"])
    XCTAssertEqual(try directorySnapshot(fixture.paths.libraryDirectory), librarySnapshot)
    XCTAssertEqual(fixture.service.loadSelection().selection, .installed(recordID: "keep"))
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path), [])

    let retried = try fixture.service.install(try fixture.service.stage(.folder(incoming)))
    XCTAssertEqual(retried.record.recordID, "incoming")
  }

  func testCopyFailureDuringStagingCleansUp() throws {
    let source = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("copyfail"))
    fixture.fileSystem.fail(.copyFile)

    assertLibraryError(try fixture.service.stage(.folder(source)), .writeFailed)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path), [])
  }

  func testPreparePurgesInterruptedStages() throws {
    let leftover = fixture.paths.stagingDirectory.appendingPathComponent("stage-old")
    try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: leftover.appendingPathComponent("record.json"))

    try fixture.service.prepare()

    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.libraryDirectory.path))
    XCTAssertEqual(fixture.service.entries(), [])
  }

  func testSelectionStoreHandlesCorruptAndFutureFiles() throws {
    try FileManager.default.createDirectory(
      at: fixture.paths.rootDirectory, withIntermediateDirectories: true)
    try Data("nope".utf8).write(to: fixture.paths.selectionURL)
    XCTAssertEqual(
      fixture.service.loadSelection(), PetSelectionLoad(selection: .original, issue: .corruptFile))
    XCTAssertEqual(fixture.service.resolveSelection().issue, .selectionFileCorrupt)
    XCTAssertTrue(try fixture.service.select(.original), "a corrupt file is rewritten")
    XCTAssertEqual(fixture.service.loadSelection(), PetSelectionLoad(selection: .original))

    try Data(#"{"schemaVersion":7,"kind":"future"}"#.utf8).write(to: fixture.paths.selectionURL)
    XCTAssertEqual(
      fixture.service.loadSelection(),
      PetSelectionLoad(selection: .original, issue: .unsupportedSchema(7)))
    assertLibraryError(try fixture.service.select(.none), .selectionStoreUnsupported)
    XCTAssertEqual(
      try String(contentsOf: fixture.paths.selectionURL, encoding: .utf8),
      #"{"schemaVersion":7,"kind":"future"}"#)
  }

  func testLicenseDeclarationsArePreservedAndUnknownIsNotBundled() throws {
    let declared = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("declared"), id: "declared",
      extraFields: [
        "license": ["name": "CC-BY-4.0", "url": "https://example.com/license"], "author": "someone",
      ])
    try Data("license text".utf8).write(to: declared.appendingPathComponent("LICENSE.txt"))
    let declaredRecord = try fixture.service.install(try fixture.service.stage(.folder(declared)))
      .record
    XCTAssertEqual(declaredRecord.licenseStatus, .externallyDeclared)
    XCTAssertEqual(
      declaredRecord.license,
      PetLicenseDeclaration(
        name: "CC-BY-4.0", url: "https://example.com/license", attribution: "someone",
        noticeFile: "LICENSE.txt"))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: fixture.paths.packageDirectory(for: "declared").appendingPathComponent(
          "LICENSE.txt"
        ).path))

    let unknown = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("unknown"), id: "unknown", seed: 9)
    let unknownRecord = try fixture.service.install(try fixture.service.stage(.folder(unknown)))
      .record
    XCTAssertEqual(unknownRecord.licenseStatus, .unknown)
    XCTAssertEqual(unknownRecord.license, PetLicenseDeclaration())
    XCTAssertFalse(
      fixture.service.entries().contains { $0.record?.licenseStatus == .bundledVerified })
  }

  func testRecordFileIsStableJSON() throws {
    let source = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("json"), id: "json")
    let record = try fixture.service.install(try fixture.service.stage(.folder(source))).record
    let data = try Data(contentsOf: fixture.paths.recordFile(for: record.recordID))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    XCTAssertEqual(object["recordID"] as? String, "json")
    XCTAssertEqual(object["licenseStatus"] as? String, "unknown")
    XCTAssertEqual((object["source"] as? [String: String])?["kind"], "folder")
    XCTAssertEqual(object["installedAt"] as? String, "2023-11-14T22:13:20Z")
  }

  func testSourceResolverClassifiesInputs() throws {
    let folder = try PetPackageFixture.writePackage(into: fixture.sourceDirectory("resolve"))
    let archive = fixture.root.appendingPathComponent("pet.codex-pet.zip")
    try ZipFixtureWriter.packageArchive(packageDirectory: folder).write(to: archive)
    let image = fixture.root.appendingPathComponent("lonely.png")
    try Data([0x89, 0x50]).write(to: image)

    XCTAssertEqual(
      try PetPackageSourceResolver.resolve(folder.path, relativeTo: fixture.root), .folder(folder))
    XCTAssertEqual(
      try PetPackageSourceResolver.resolve("pet.codex-pet.zip", relativeTo: fixture.root),
      .archive(archive))
    XCTAssertEqual(
      try PetPackageSourceResolver.resolve(
        "https://codex-pets.net/#/pets/yuumi", relativeTo: fixture.root),
      .url(URL(string: "https://codex-pets.net/#/pets/yuumi")!))
    assertLibraryError(
      try PetPackageSourceResolver.resolve(image.path, relativeTo: fixture.root), .unsupportedSource
    )
    assertLibraryError(
      try PetPackageSourceResolver.resolve("missing", relativeTo: fixture.root), .sourceUnavailable)
    assertLibraryError(
      try PetPackageSourceResolver.resolve("  ", relativeTo: fixture.root), .unsupportedSource)
  }
}
