import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexSetupServiceTests: XCTestCase {
  func testDryRunDoesNotCreateHooksBackupOrTrustState() throws {
    let fixture = fixture()

    let change = try fixture.service.connect(dryRun: true)

    XCTAssertTrue(change.dryRun)
    XCTAssertEqual(change.status, .connected)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.hooksURL.path))
    XCTAssertEqual(fixture.trust.activateCalls, 0)
    XCTAssertEqual(try backupFiles(in: fixture.hooksURL.deletingLastPathComponent()), [])
  }

  func testConnectAndDisconnectPreserveOtherHooksAndUseTrustManager() throws {
    let fixture = fixture()
    try FileManager.default.createDirectory(
      at: fixture.hooksURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(
      #"{"description":"keep","hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"other"}]}]}}"#
        .utf8
    ).write(to: fixture.hooksURL)

    let connected = try fixture.service.connect(dryRun: false)
    let installed = try Data(contentsOf: fixture.hooksURL)
    fixture.trust.inspection = CodexHookTrustInspection(
      hookCount: CodexHookConfiguration.eventNames.count,
      trustedHookCount: CodexHookConfiguration.eventNames.count,
      keys: ["owned-1", "owned-2"]
    )
    let disconnected = try fixture.service.disconnect(dryRun: false)
    let removed =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.hooksURL)
      ) as? [String: Any]

    XCTAssertEqual(connected.trustedHookCount, CodexHookConfiguration.eventNames.count)
    XCTAssertEqual(fixture.trust.activateCalls, 1)
    XCTAssertEqual(
      try CodexHookConfiguration().ownedHandlerCount(in: installed),
      CodexHookConfiguration.eventNames.count
    )
    XCTAssertEqual(disconnected.status, .notConfigured)
    XCTAssertEqual(fixture.trust.removedKeys, ["owned-1", "owned-2"])
    XCTAssertEqual(removed?["description"] as? String, "keep")
    let hooks = removed?["hooks"] as? [String: Any]
    XCTAssertNotNil(hooks?["PreCompact"])
    XCTAssertEqual(try backupFiles(in: fixture.hooksURL.deletingLastPathComponent()).count, 2)
  }

  func testTrustFailureRollsBackNewHooksFile() throws {
    let fixture = fixture()
    fixture.trust.activateError = CodexHookTrustManager.Error.trustVerificationFailed

    XCTAssertThrowsError(try fixture.service.connect(dryRun: false)) {
      XCTAssertEqual($0 as? CodexSetupServiceError, .trustFailed)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.hooksURL.path))
  }

  func testReconnectReplacesPreviouslyOwnedTrustKeysWithoutExtraBackup() throws {
    let fixture = fixture()
    _ = try fixture.service.connect(dryRun: false)
    fixture.trust.inspection = CodexHookTrustInspection(
      hookCount: CodexHookConfiguration.eventNames.count,
      trustedHookCount: CodexHookConfiguration.eventNames.count,
      keys: ["old-owned-key"]
    )

    let reconnected = try fixture.service.connect(dryRun: false)

    XCTAssertEqual(fixture.trust.replacedKeys, ["old-owned-key"])
    XCTAssertTrue(reconnected.changed)
    XCTAssertEqual(try backupFiles(in: fixture.hooksURL.deletingLastPathComponent()), [])
  }

  func testConcurrentHookChangeIsNotOverwrittenOrBackedUp() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data(#"{"description":"before"}"#.utf8).write(to: hooksURL)
    let trust = FakeTrustManager()
    let service = CodexSetupService(
      hooksURL: hooksURL,
      executableURL: URL(fileURLWithPath: "/bin/cat"),
      cwd: directory,
      trustManager: trust,
      now: { Date(timeIntervalSince1970: 1) },
      beforeWrite: {
        try! Data(#"{"description":"concurrent"}"#.utf8).write(to: hooksURL)
      }
    )

    XCTAssertThrowsError(try service.connect(dryRun: false)) {
      XCTAssertEqual($0 as? CodexSetupServiceError, .concurrentModification)
    }
    XCTAssertEqual(
      String(decoding: try Data(contentsOf: hooksURL), as: UTF8.self),
      #"{"description":"concurrent"}"#
    )
    XCTAssertEqual(try backupFiles(in: directory), [])
  }

  func testSymlinkHooksFileIsRejected() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    let target = directory.appendingPathComponent("target.json")
    try Data("{}".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: hooksURL, withDestinationURL: target)
    let trust = FakeTrustManager()
    let service = service(hooksURL: hooksURL, trust: trust)

    XCTAssertThrowsError(try service.connect(dryRun: false)) {
      XCTAssertEqual($0 as? CodexSetupServiceError, .unsafeHooksTarget)
    }
    XCTAssertEqual(try Data(contentsOf: target), Data("{}".utf8))
  }

  private func fixture() -> (
    service: CodexSetupService,
    hooksURL: URL,
    trust: FakeTrustManager
  ) {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent(".codex/hooks.json")
    let trust = FakeTrustManager()
    return (service(hooksURL: hooksURL, trust: trust), hooksURL, trust)
  }

  private func service(
    hooksURL: URL,
    trust: FakeTrustManager
  ) -> CodexSetupService {
    CodexSetupService(
      hooksURL: hooksURL,
      executableURL: URL(fileURLWithPath: "/bin/cat"),
      cwd: hooksURL.deletingLastPathComponent(),
      trustManager: trust,
      now: { Date(timeIntervalSince1970: 1) },
      beforeWrite: {}
    )
  }

  private func backupFiles(in directory: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.contains("omapet-backup") }
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

private final class FakeTrustManager: CodexHookTrustManaging, @unchecked Sendable {
  var inspection = CodexHookTrustInspection(
    hookCount: CodexHookConfiguration.eventNames.count,
    trustedHookCount: CodexHookConfiguration.eventNames.count,
    keys: Set((0..<CodexHookConfiguration.eventNames.count).map { "owned-\($0)" })
  )
  var activateError: Error?
  var activateCalls = 0
  var removedKeys: Set<String> = []
  var replacedKeys: Set<String> = []

  func inspect(cwd: URL) throws -> CodexHookTrustInspection { inspection }

  func keysForRemoval(cwd: URL) throws -> Set<String> { inspection.keys }

  func activate(
    cwd: URL,
    expectedHookCount: Int,
    replacing keys: Set<String>
  ) throws -> CodexHookTrustChange {
    activateCalls += 1
    replacedKeys = keys
    if let activateError { throw activateError }
    return CodexHookTrustChange(trustedHookCount: expectedHookCount, changed: true)
  }

  func removeTrustedHookKeys(_ keys: Set<String>) throws -> Bool {
    removedKeys = keys
    return !keys.isEmpty
  }
}
