import AgentPetLibrary
import Foundation
import XCTest

@testable import AgentPetLibrary

final class PetPackageFingerprintTests: XCTestCase {
  func testCanonicalManifestIgnoresKeyOrderAndWhitespace() throws {
    let compact = Data(#"{"id":"a","spriteVersionNumber":2,"displayName":"A"}"#.utf8)
    let spaced = Data(
      "{ \"displayName\": \"A\",\n  \"spriteVersionNumber\": 2, \"id\": \"a\" }".utf8)
    let different = Data(#"{"id":"a","spriteVersionNumber":1,"displayName":"A"}"#.utf8)
    let sheet = PetPackageFingerprint.spritesheetDigest(Data([1, 2, 3]))

    XCTAssertEqual(
      try PetPackageFingerprint.packageDigest(manifest: compact, spritesheetDigest: sheet),
      try PetPackageFingerprint.packageDigest(manifest: spaced, spritesheetDigest: sheet))
    XCTAssertNotEqual(
      try PetPackageFingerprint.packageDigest(manifest: compact, spritesheetDigest: sheet),
      try PetPackageFingerprint.packageDigest(manifest: different, spritesheetDigest: sheet))
    XCTAssertNotEqual(
      try PetPackageFingerprint.packageDigest(manifest: compact, spritesheetDigest: sheet),
      try PetPackageFingerprint.packageDigest(
        manifest: compact,
        spritesheetDigest: PetPackageFingerprint.spritesheetDigest(Data([1, 2, 4]))))
    XCTAssertEqual(sheet.count, 64)
    XCTAssertThrowsError(
      try PetPackageFingerprint.packageDigest(manifest: Data("{".utf8), spritesheetDigest: sheet))
  }

  func testLicenseReaderDistinguishesDeclaredAndUnknown() {
    let string = PetLicenseReader.declaration(
      manifest: Data(#"{"id":"x","license":"MIT"}"#.utf8), rootFileNames: [],
      fallbackAttribution: nil)
    XCTAssertEqual(string, PetLicenseDeclaration(name: "MIT"))
    XCTAssertEqual(PetLicenseReader.status(for: string), .externallyDeclared)

    let object = PetLicenseReader.declaration(
      manifest: Data(#"{"id":"x","license":{"spdx":"CC0-1.0","url":"https://example.com"}}"#.utf8),
      rootFileNames: ["readme.md"], fallbackAttribution: "owner")
    XCTAssertEqual(
      object,
      PetLicenseDeclaration(name: "CC0-1.0", url: "https://example.com", attribution: "owner"))

    let notice = PetLicenseReader.declaration(
      manifest: Data(#"{"id":"x"}"#.utf8), rootFileNames: ["spritesheet.webp", "COPYING"],
      fallbackAttribution: nil)
    XCTAssertEqual(notice.noticeFile, "COPYING")
    XCTAssertEqual(PetLicenseReader.status(for: notice), .externallyDeclared)

    let unknown = PetLicenseReader.declaration(
      manifest: Data(#"{"id":"x","author":"  "}"#.utf8), rootFileNames: ["pet.json"],
      fallbackAttribution: "owner")
    XCTAssertEqual(unknown, PetLicenseDeclaration(attribution: "owner"))
    XCTAssertEqual(PetLicenseReader.status(for: unknown), .unknown)
  }

  func testRecordIDProposalReservesSelectionWordsAndAvoidsCollisions() {
    let fingerprint = String(repeating: "ab", count: 32)
    XCTAssertEqual(
      PetRecordIDPolicy.propose(manifestID: "cat", fingerprint: fingerprint, takenIDs: []),
      "cat")
    XCTAssertEqual(
      PetRecordIDPolicy.propose(
        manifestID: "cat", fingerprint: fingerprint, takenIDs: ["cat"]),
      "cat-abababab")
    XCTAssertEqual(
      PetRecordIDPolicy.propose(
        manifestID: "cat", fingerprint: fingerprint, takenIDs: ["cat", "cat-abababab"]),
      "cat-abababababababab")
    XCTAssertEqual(
      PetRecordIDPolicy.propose(manifestID: "none", fingerprint: fingerprint, takenIDs: []),
      "none-abababab")
    XCTAssertEqual(
      PetRecordIDPolicy.propose(
        manifestID: "original", fingerprint: fingerprint, takenIDs: []),
      "original-abababab")
  }

  func testRecordIDPolicyAcceptsExtendedFingerprintSuffixesItProposes() {
    let fingerprint = String(repeating: "a", count: PetRecordIDPolicy.fingerprintLength)
    let taken = Set([
      "cat",
      "cat-" + String(repeating: "a", count: 8),
      "cat-" + String(repeating: "a", count: 16),
    ])

    let proposed = PetRecordIDPolicy.propose(
      manifestID: "cat",
      fingerprint: fingerprint,
      takenIDs: taken
    )

    XCTAssertEqual(proposed, "cat-" + String(repeating: "a", count: 24))
    XCTAssertTrue(PetRecordIDPolicy.isValid(proposed))
  }
}
