import AgentPetLibrary
import AgentPetSprites
import AgentPetTestSupport
import Foundation
import XCTest

@testable import AgentPetLibrary

final class PetArchiveInstallTests: XCTestCase {
  private var fixture: LibraryFixture!
  private var package: URL!

  override func setUpWithError() throws {
    fixture = try LibraryFixture()
    package = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("zipped"), id: "zipped", displayName: "Zipped", version: 2)
  }

  override func tearDown() {
    fixture.remove()
    fixture = nil
  }

  private func write(_ archive: Data, name: String = "pet.codex-pet.zip") throws -> URL {
    let url = fixture.root.appendingPathComponent(name)
    try archive.write(to: url)
    return url
  }

  func testStoredArchiveAtRootMatchesFolderInstall() throws {
    let folderStaged = try fixture.service.stage(.folder(package))
    let folderInspection = folderStaged.inspection
    fixture.service.discard(folderStaged)
    let archive = try write(ZipFixtureWriter.packageArchive(packageDirectory: package))

    let staged = try fixture.service.stage(.archive(archive))
    XCTAssertEqual(staged.inspection.packageFingerprint, folderInspection.packageFingerprint)
    XCTAssertEqual(
      staged.inspection.spritesheetFingerprint, folderInspection.spritesheetFingerprint)
    XCTAssertEqual(staged.inspection.licenseStatus, folderInspection.licenseStatus)
    XCTAssertEqual(staged.inspection.warnings, folderInspection.warnings)
    XCTAssertEqual(staged.inspection.source, .archive(fileName: "pet.codex-pet.zip"))

    let outcome = try fixture.service.install(staged)
    XCTAssertEqual(outcome.record.recordID, "zipped")
    XCTAssertEqual(
      try directorySnapshot(fixture.paths.packageDirectory(for: "zipped")),
      try directorySnapshot(package))
  }

  func testDeflatedNestedArchiveWithMacOSJunkInstalls() throws {
    let archive = try write(
      ZipFixtureWriter.packageArchive(
        packageDirectory: package,
        root: "zipped/",
        method: .deflate,
        extraEntries: [
          ZipFixtureEntry(name: "zipped/", isDirectory: true),
          ZipFixtureEntry.file("__MACOSX/zipped/._pet.json", Data([0, 1, 2])),
          ZipFixtureEntry.file("zipped/.DS_Store", Data([9])),
          ZipFixtureEntry.file("zipped/LICENSE", Data("MIT".utf8), method: .deflate),
        ]
      )
    )

    let staged = try fixture.service.stage(.archive(archive))
    XCTAssertEqual(staged.inspection.license.noticeFile, "LICENSE")
    XCTAssertEqual(staged.inspection.licenseStatus, .externallyDeclared)
    let outcome = try fixture.service.install(staged)
    let installed = try directorySnapshot(
      fixture.paths.packageDirectory(for: outcome.record.recordID))
    XCTAssertEqual(Set(installed.keys), ["pet.json", "spritesheet.png", "LICENSE"])
    XCTAssertEqual(
      installed["spritesheet.png"],
      try Data(contentsOf: package.appendingPathComponent("spritesheet.png")))
  }

  func testArchiveMadeByZipToolInstalls() throws {
    let archive = fixture.root.appendingPathComponent("tool.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = package.deletingLastPathComponent()
    process.arguments = ["-q", "-r", archive.path, package.lastPathComponent]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)

    let outcome = try fixture.service.install(try fixture.service.stage(.archive(archive)))
    XCTAssertEqual(outcome.record.manifestID, "zipped")
  }

  func testUnsafeArchivesAreRejectedWithoutWritingOutsideStage() throws {
    let manifest = try Data(contentsOf: package.appendingPathComponent("pet.json"))
    let sheet = try Data(contentsOf: package.appendingPathComponent("spritesheet.png"))
    let unsafeCases: [(String, [ZipFixtureEntry], String)] = [
      (
        "traversal",
        [.file("../pet.json", manifest), .file("spritesheet.png", sheet)],
        "unsafe_entry_path"
      ),
      (
        "absolute",
        [.file("/tmp/pet.json", manifest), .file("spritesheet.png", sheet)],
        "unsafe_entry_path"
      ),
      (
        "symlink",
        [
          .file("pet.json", manifest), .file("spritesheet.png", sheet),
          ZipFixtureEntry(name: "LICENSE", data: Data("/etc/hosts".utf8), isSymbolicLink: true),
        ],
        "symbolic_link"
      ),
      (
        "duplicate",
        [
          .file("pet.json", manifest), .file("PET.JSON", manifest), .file("spritesheet.png", sheet),
        ],
        "duplicate_entry"
      ),
      (
        "two-roots",
        [.file("a/pet.json", manifest), .file("b/spritesheet.png", sheet)],
        "package_root"
      ),
      (
        "no-manifest",
        [.file("spritesheet.png", sheet)],
        "package_root"
      ),
      (
        "corrupt-crc",
        [
          ZipFixtureEntry(name: "pet.json", data: manifest, corruptCRC: true),
          .file("spritesheet.png", sheet),
        ],
        "corrupt_entry"
      ),
    ]
    for (name, entries, reason) in unsafeCases {
      let archive = try write(ZipFixtureWriter.archive(entries), name: "\(name).zip")
      assertLibraryError(
        try fixture.service.stage(.archive(archive)), .unsafePackage, reason: reason)
    }
    assertLibraryError(
      try fixture.service.stage(.archive(try write(Data("not a zip".utf8), name: "text.zip"))),
      .unsafePackage, reason: "not_a_zip_archive")

    let outside = fixture.root.appendingPathComponent("pet.json")
    XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    XCTAssertEqual(fixture.service.entries(), [])
    XCTAssertEqual(
      (try? FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path))
        ?? [],
      [])
  }

  func testOversizedArchivesAreRejectedBeforeExtraction() throws {
    let manifest = try Data(contentsOf: package.appendingPathComponent("pet.json"))
    let sheet = try Data(contentsOf: package.appendingPathComponent("spritesheet.png"))

    let tooMany = ZipFixtureWriter.archive(
      [.file("pet.json", manifest), .file("spritesheet.png", sheet)]
        + (0..<PetLibraryPolicy.maximumArchiveEntries).map { .file("extra-\($0).txt", Data([1])) })
    assertLibraryError(
      try fixture.service.stage(.archive(try write(tooMany, name: "many.zip"))),
      .oversizedPackage, reason: "too_many_entries")

    let declaredHuge = ZipFixtureWriter.archive([
      .file("pet.json", manifest),
      ZipFixtureEntry(
        name: "spritesheet.png", data: sheet,
        declaredUncompressedSize: PetSpritePackageLoader.maximumSpritesheetBytes + 1),
    ])
    assertLibraryError(
      try fixture.service.stage(.archive(try write(declaredHuge, name: "huge.zip"))),
      .oversizedPackage, reason: "entry_too_large")

    let bigFile = fixture.root.appendingPathComponent("bigfile.zip")
    FileManager.default.createFile(atPath: bigFile.path, contents: nil)
    let handle = try FileHandle(forWritingTo: bigFile)
    try handle.truncate(atOffset: UInt64(PetLibraryPolicy.maximumArchiveBytes + 1))
    try handle.close()
    assertLibraryError(
      try fixture.service.stage(.archive(bigFile)), .oversizedPackage, reason: "archive_too_large")
  }

  func testZipReaderRejectsEncryptionAndUnknownMethods() throws {
    var archive = ZipFixtureWriter.archive([.file("pet.json", Data("{}".utf8))])
    let reader = try ZipArchiveReader(data: archive)
    XCTAssertEqual(reader.entries.map(\.name), ["pet.json"])
    XCTAssertEqual(try reader.extract(reader.entries[0]), Data("{}".utf8))

    let centralOffset = archive.count - 22 - 46 - "pet.json".utf8.count
    archive[centralOffset + 8] = 0x01
    let encrypted = try ZipArchiveReader(data: archive)
    XCTAssertTrue(encrypted.entries[0].isEncrypted)
    XCTAssertThrowsError(try encrypted.extract(encrypted.entries[0]))

    archive[centralOffset + 8] = 0x00
    archive[centralOffset + 10] = 0x0C
    let unknownMethod = try ZipArchiveReader(data: archive)
    XCTAssertThrowsError(try unknownMethod.extract(unknownMethod.entries[0])) {
      XCTAssertEqual($0 as? ZipArchiveError, .unsupportedFeature("compression_method_12"))
    }
  }
}
