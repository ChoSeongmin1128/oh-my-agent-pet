import Foundation
import OmapetSupport
import XCTest

final class OmapetCommandRunnerTests: XCTestCase {
  func testVersionTextIsStable() {
    let result = OmapetCommandRunner().run(arguments: ["version"])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.standardOutput, "Oh My Agent Pet 0.0.0-dev\n")
    XCTAssertEqual(result.standardError, "")
  }

  func testConventionalHelpAndVersionFlagsRemainSupported() {
    let runner = OmapetCommandRunner()

    XCTAssertEqual(runner.run(arguments: ["--help"]).exitCode, 0)
    XCTAssertTrue(runner.run(arguments: ["--help"]).standardOutput.contains("Usage:"))
    XCTAssertEqual(
      runner.run(arguments: ["--version"]).standardOutput,
      "Oh My Agent Pet 0.0.0-dev\n"
    )
  }

  func testVersionJSONIsMachineReadable() throws {
    let result = OmapetCommandRunner().run(arguments: ["version", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String]
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["name"], "Oh My Agent Pet")
    XCTAssertEqual(object["version"], "0.0.0-dev")
  }

  func testSetupStatusDoesNotClaimConnection() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }
    let result = fixture.runner.run(arguments: ["setup", "status", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["status"] as? String, "notConfigured")
    XCTAssertEqual(object["provider"] as? String, "claude")
  }

  func testDoctorReportsConnectionPetAndEventLogHealthWithoutMutatingFreshHome() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }
    let result = fixture.runner.run(arguments: ["doctor", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )
    let checks = try XCTUnwrap(object["checks"] as? [[String: Any]])
    let byID = Dictionary(
      uniqueKeysWithValues: checks.compactMap { check -> (String, [String: Any])? in
        guard let id = check["id"] as? String else { return nil }
        return (id, check)
      })

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["status"] as? String, "warning")
    XCTAssertEqual(byID["runtime"]?["status"] as? String, "pass")
    XCTAssertEqual(byID["claude_connection"]?["detail"] as? String, "not_configured")
    XCTAssertEqual(byID["codex_connection"]?["detail"] as? String, "not_configured")
    XCTAssertEqual(byID["pet_selection"]?["status"] as? String, "pass")
    XCTAssertEqual(byID["event_log"]?["detail"] as? String, "not_created")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.home
          .appendingPathComponent("Library/Application Support/Oh My Agent Pet").path
      ),
      "doctor must be read-only on a fresh home"
    )
  }

  func testDoctorFailsForUnsafeEventLogTarget() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }
    let support = fixture.home.appendingPathComponent(
      "Library/Application Support/Oh My Agent Pet",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let target = support.appendingPathComponent("target")
    try Data().write(to: target)
    try FileManager.default.createSymbolicLink(
      at: support.appendingPathComponent("events.ndjson"),
      withDestinationURL: target
    )

    let result = fixture.runner.run(arguments: ["doctor", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )
    let checks = try XCTUnwrap(object["checks"] as? [[String: Any]])
    let eventLog = try XCTUnwrap(checks.first { $0["id"] as? String == "event_log" })

    XCTAssertEqual(result.exitCode, 74)
    XCTAssertEqual(object["status"] as? String, "fail")
    XCTAssertEqual(eventLog["detail"] as? String, "unsafe_type")
  }

  func testUnknownCommandUsesUsageExitCode() {
    let result = OmapetCommandRunner().run(arguments: ["connect"])

    XCTAssertEqual(result.exitCode, 64)
    XCTAssertTrue(result.standardOutput.isEmpty)
    XCTAssertTrue(result.standardError.contains("Unsupported arguments"))
  }

  func testSetupConnectDryRunAndActualRoundTrip() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }

    let dryRun = fixture.runner.run(arguments: [
      "setup", "connect", "claude", "--dry-run", "--json",
    ])
    XCTAssertEqual(dryRun.exitCode, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.settingsURL.path))

    let connected = fixture.runner.run(arguments: ["setup", "connect", "claude", "--json"])
    let status = fixture.runner.run(arguments: ["setup", "status", "--json"])
    let disconnected = fixture.runner.run(arguments: [
      "setup", "disconnect", "claude", "--json",
    ])

    XCTAssertEqual(connected.exitCode, 0)
    XCTAssertTrue(connected.standardOutput.contains(#""status":"connected""#))
    XCTAssertTrue(status.standardOutput.contains(#""status":"connected""#))
    XCTAssertEqual(disconnected.exitCode, 0)
    XCTAssertTrue(disconnected.standardOutput.contains(#""status":"notConfigured""#))
  }

  func testSetupInvalidJSONHasDeterministicMachineError() throws {
    let fixture = try CLIFixture(settings: "{broken")
    defer { fixture.remove() }

    let result = fixture.runner.run(arguments: ["setup", "connect", "claude", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String]
    )

    XCTAssertEqual(result.exitCode, 65)
    XCTAssertEqual(object, ["status": "error", "code": "invalid_configuration"])
    XCTAssertTrue(result.standardError.isEmpty)
  }

  func testHookCommandNeverWritesToStandardStreamsAndRecordsAllowedEvent() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }
    let payload = Data(
      #"{"hook_event_name":"Stop","session_id":"session","cwd":"/tmp","prompt":"secret"}"#.utf8
    )

    let result = fixture.runner.run(arguments: ["hook", "claude"], standardInput: payload)
    let invalid = fixture.runner.run(
      arguments: ["hook", "claude"],
      standardInput: Data("{".utf8)
    )
    let eventsURL = fixture.home.appendingPathComponent(
      "Library/Application Support/Oh My Agent Pet/events.ndjson"
    )
    let stored = try String(contentsOf: eventsURL, encoding: .utf8)

    XCTAssertEqual(result, OmapetCommandResult(exitCode: 0))
    XCTAssertEqual(invalid, OmapetCommandResult(exitCode: 0))
    XCTAssertFalse(stored.contains("secret"))
  }

  func testCodexHookCommandStoresProviderAndTurnInSharedEventLog() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }
    let payload = Data(
      #"{"hook_event_name":"PermissionRequest","session_id":"session","turn_id":"turn-1","cwd":"/tmp","prompt":"secret"}"#
        .utf8
    )

    let result = fixture.runner.run(arguments: ["hook", "codex"], standardInput: payload)
    let eventsURL = fixture.home.appendingPathComponent(
      "Library/Application Support/Oh My Agent Pet/events.ndjson"
    )
    let stored = try String(contentsOf: eventsURL, encoding: .utf8)

    XCTAssertEqual(result, OmapetCommandResult(exitCode: 0))
    XCTAssertTrue(stored.contains(#""provider":"codex""#))
    XCTAssertTrue(stored.contains(#""turn_id":"turn-1""#))
    XCTAssertFalse(stored.contains("secret"))
  }

  func testCodexSetupStatusAndDryRunNeedNoCodexMutation() throws {
    let fixture = try CLIFixture()
    defer { fixture.remove() }

    let status = fixture.runner.run(arguments: ["setup", "status", "codex", "--json"])
    let dryRun = fixture.runner.run(arguments: [
      "setup", "connect", "codex", "--dry-run", "--json",
    ])
    let hooksURL = fixture.home.appendingPathComponent(".codex/hooks.json")

    XCTAssertEqual(status.exitCode, 0)
    XCTAssertTrue(status.standardOutput.contains(#""status":"not_configured""#))
    XCTAssertEqual(dryRun.exitCode, 0)
    XCTAssertTrue(dryRun.standardOutput.contains(#""trusted_hook_count":8"#))
    XCTAssertFalse(FileManager.default.fileExists(atPath: hooksURL.path))
  }
}

private struct CLIFixture {
  let home: URL
  let settingsURL: URL
  let runner: OmapetCommandRunner

  init(settings: String? = nil) throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let executable = home.appendingPathComponent("omapet")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: UInt16(0o700))],
      ofItemAtPath: executable.path
    )
    settingsURL = home.appendingPathComponent(".claude/settings.json")
    if let settings {
      try FileManager.default.createDirectory(
        at: settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try settings.write(to: settingsURL, atomically: true, encoding: .utf8)
    }
    runner = OmapetCommandRunner(
      environment: [:],
      homeDirectory: home,
      executableURL: executable
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: home)
  }
}
