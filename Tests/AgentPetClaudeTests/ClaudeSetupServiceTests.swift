import Foundation
import XCTest

@testable import AgentPetClaude

final class ClaudeSetupServiceTests: XCTestCase {
  func testDryRunDoesNotCreateOrModifySettings() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }

    let result = try fixture.service.connect(dryRun: true)

    XCTAssertTrue(result.changed)
    XCTAssertTrue(result.dryRun)
    XCTAssertNil(result.backupPath)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.settingsURL.path))
  }

  func testConnectIsIdempotentAndCreatesBackupOnlyForChange() throws {
    let fixture = try Fixture(settings: #"{"theme":"dark"}"#)
    defer { fixture.remove() }

    let first = try fixture.service.connect(dryRun: false)
    let installed = try Data(contentsOf: fixture.settingsURL)
    let second = try fixture.service.connect(dryRun: false)

    XCTAssertTrue(first.changed)
    XCTAssertNotNil(first.backupPath)
    XCTAssertFalse(second.changed)
    XCTAssertNil(second.backupPath)
    XCTAssertEqual(try fixture.service.status().status, .connected)
    XCTAssertEqual(installed, try Data(contentsOf: fixture.settingsURL))
    XCTAssertEqual(try fixture.backups().count, 1)
    XCTAssertEqual(
      try String(contentsOf: XCTUnwrap(first.backupPath).asFileURL, encoding: .utf8),
      #"{"theme":"dark"}"#
    )
  }

  func testConnectDoesNotClaimEnabledWhenAllHooksAreDisabled() throws {
    let fixture = try Fixture(settings: #"{"disableAllHooks":true}"#)
    defer { fixture.remove() }

    let result = try fixture.service.connect(dryRun: false)

    XCTAssertEqual(result.status, .connectedButDisabled)
    XCTAssertEqual(try fixture.service.status().status, .connectedButDisabled)
  }

  func testDisconnectPreservesOtherToolEdits() throws {
    let fixture = try Fixture(settings: #"{"theme":"light"}"#)
    defer { fixture.remove() }
    _ = try fixture.service.connect(dryRun: false)
    var root = try fixture.settingsObject()
    root["theme"] = "dark"
    root["otherTool"] = true
    try JSONSerialization.data(withJSONObject: root).write(to: fixture.settingsURL)

    let result = try fixture.service.disconnect(dryRun: false)
    let disconnected = try fixture.settingsObject()

    XCTAssertTrue(result.changed)
    XCTAssertEqual(disconnected["theme"] as? String, "dark")
    XCTAssertEqual(disconnected["otherTool"] as? Bool, true)
    XCTAssertNil(disconnected["hooks"])
    XCTAssertEqual(try fixture.service.status().status, .notConfigured)
  }

  func testDisconnectWithoutHooksDoesNotCreateSettings() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }

    let result = try fixture.service.disconnect(dryRun: false)

    XCTAssertFalse(result.changed)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.settingsURL.path))
  }

  func testConcurrentSettingsChangeIsNotOverwrittenOrBackedUp() throws {
    let home = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let executable = try makeExecutable(in: home)
    let settingsURL = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(#"{"theme":"light"}"#.utf8).write(to: settingsURL)
    let service = ClaudeSetupService(
      homeDirectory: home,
      environment: [:],
      executableURL: executable,
      now: Date.init,
      beforeWrite: {
        try? Data(#"{"theme":"dark","external":true}"#.utf8).write(to: settingsURL)
      }
    )

    XCTAssertThrowsError(try service.connect(dryRun: false)) {
      XCTAssertEqual($0 as? ClaudeSetupServiceError, .concurrentModification)
    }
    XCTAssertEqual(
      try String(contentsOf: settingsURL, encoding: .utf8),
      #"{"theme":"dark","external":true}"#
    )
    let files = try FileManager.default.contentsOfDirectory(
      atPath: settingsURL.deletingLastPathComponent().path)
    XCTAssertEqual(files, ["settings.json"])
  }

  func testInvalidJSONAndSymlinkAreLeftUntouched() throws {
    let invalid = try Fixture(settings: "{broken")
    defer { invalid.remove() }

    XCTAssertThrowsError(try invalid.service.connect(dryRun: false)) {
      XCTAssertEqual(
        $0 as? ClaudeSetupServiceError,
        .configuration(.invalidJSON)
      )
    }
    XCTAssertEqual(try String(contentsOf: invalid.settingsURL, encoding: .utf8), "{broken")
    XCTAssertTrue(try invalid.backups().isEmpty)

    let symlink = try Fixture()
    defer { symlink.remove() }
    try FileManager.default.createDirectory(
      at: symlink.settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let target = symlink.home.appendingPathComponent("target.json")
    try Data("{}".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
      at: symlink.settingsURL,
      withDestinationURL: target
    )
    XCTAssertThrowsError(try symlink.service.status()) {
      XCTAssertEqual($0 as? ClaudeSetupServiceError, .unsafeSettingsTarget)
    }
  }

  func testClaudeConfigDirectoryEnvironmentIsRespected() throws {
    let home = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let executable = try makeExecutable(in: home)
    let service = ClaudeSetupService(
      homeDirectory: home,
      environment: ["CLAUDE_CONFIG_DIR": "~/custom-claude"],
      executableURL: executable
    )

    XCTAssertEqual(
      service.settingsURL.standardizedFileURL,
      home.appendingPathComponent("custom-claude/settings.json").standardizedFileURL
    )
  }
}

private struct Fixture {
  let home: URL
  let settingsURL: URL
  let service: ClaudeSetupService

  init(settings: String? = nil) throws {
    home = temporaryDirectory()
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let executable = try makeExecutable(in: home)
    service = ClaudeSetupService(
      homeDirectory: home,
      environment: [:],
      executableURL: executable,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    settingsURL = service.settingsURL
    if let settings {
      try FileManager.default.createDirectory(
        at: settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try settings.write(to: settingsURL, atomically: true, encoding: .utf8)
    }
  }

  func settingsObject() throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
    )
  }

  func backups() throws -> [URL] {
    let directory = settingsURL.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("settings.json.omapet-backup-") }
  }

  func remove() {
    try? FileManager.default.removeItem(at: home)
  }
}

private func temporaryDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
}

private func makeExecutable(in directory: URL) throws -> URL {
  let executable = directory.appendingPathComponent("omapet")
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
  try FileManager.default.setAttributes(
    [.posixPermissions: NSNumber(value: UInt16(0o700))],
    ofItemAtPath: executable.path
  )
  return executable
}

extension String {
  fileprivate var asFileURL: URL { URL(fileURLWithPath: self) }
}
