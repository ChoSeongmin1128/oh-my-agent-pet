import AgentPetInfrastructure
import Foundation
import XCTest

final class SecureConfigurationFileStoreTests: XCTestCase {
  func testReplaceBacksUpPreservesPermissionsAndRollbackRestoresOriginal() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("settings.json")
    let original = Data(#"{"keep":true}"#.utf8)
    try original.write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    let store = SecureConfigurationFileStore(
      url: url,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let mutation = try XCTUnwrap(
      store.replace(with: Data(#"{"changed":true}"#.utf8), expected: original)
    )

    XCTAssertNotNil(mutation.backupURL)
    XCTAssertEqual(try Data(contentsOf: mutation.backupURL!), original)
    XCTAssertEqual(
      (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?
        .uint16Value,
      0o640
    )

    try store.rollback(mutation, original: original)
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testRejectsSymlinkAndConcurrentModification() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("target")
    try Data("{}".utf8).write(to: target)
    let link = root.appendingPathComponent("settings.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    XCTAssertThrowsError(try SecureConfigurationFileStore(url: link).read(defaultData: Data())) {
      XCTAssertEqual($0 as? SecureConfigurationFileError, .unsafeTarget)
    }

    try FileManager.default.removeItem(at: link)
    try Data(#"{"a":1}"#.utf8).write(to: link)
    let store = SecureConfigurationFileStore(url: link)
    XCTAssertThrowsError(
      try store.replace(
        with: Data(#"{"a":2}"#.utf8),
        expected: Data(#"{"stale":true}"#.utf8)
      )
    ) {
      XCTAssertEqual($0 as? SecureConfigurationFileError, .concurrentModification)
    }
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "omapet-infra-\(UUID().uuidString)",
      isDirectory: true
    )
  }
}
