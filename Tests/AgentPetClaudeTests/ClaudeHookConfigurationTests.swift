import AgentPetClaude
import Foundation
import XCTest

final class ClaudeHookConfigurationTests: XCTestCase {
  private let executable = URL(
    fileURLWithPath: "/Applications/Oh My Agent Pet.app/Contents/MacOS/omapet")

  func testInstallPreservesExistingSettingsAndHooks() throws {
    let input = Data(
      #"{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other"}]}]}}"#.utf8
    )
    let configuration = ClaudeHookConfiguration()

    let installed = try configuration.installing(in: input, executableURL: executable)
    let root = try jsonObject(installed)

    XCTAssertEqual(root["theme"] as? String, "dark")
    XCTAssertEqual(
      try configuration.ownedHandlerCount(in: installed), ClaudeHookConfiguration.eventNames.count)
    XCTAssertEqual(otherCommandCount(in: root, command: "/other"), 1)
    XCTAssertEqual(
      try configuration.installationState(in: installed, executableURL: executable),
      .connected
    )
  }

  func testInstallIsIdempotentAndUpdatesMovedExecutable() throws {
    let configuration = ClaudeHookConfiguration()
    let first = try configuration.installing(in: Data("{}".utf8), executableURL: executable)
    let same = try configuration.installing(in: first, executableURL: executable)
    let moved = URL(fileURLWithPath: "/opt/Oh My Agent Pet.app/Contents/MacOS/omapet")
    let updated = try configuration.installing(in: same, executableURL: moved)

    XCTAssertEqual(first, same)
    XCTAssertEqual(
      try configuration.ownedHandlerCount(in: updated), ClaudeHookConfiguration.eventNames.count)
    XCTAssertEqual(
      try configuration.installationState(in: updated, executableURL: moved), .connected)
    XCTAssertEqual(
      try configuration.installationState(in: updated, executableURL: executable), .needsRepair)
  }

  func testRemoveDropsOnlyOwnedHandlersAndKeepsLaterEdits() throws {
    let configuration = ClaudeHookConfiguration()
    let installed = try configuration.installing(in: Data("{}".utf8), executableURL: executable)
    var edited = try jsonObject(installed)
    edited["userAddedAfterConnect"] = true
    var hooks = try XCTUnwrap(edited["hooks"] as? [String: Any])
    hooks["Stop", default: []] =
      try XCTUnwrap(hooks["Stop"] as? [[String: Any]]) + [
        ["hooks": [["type": "command", "command": "/other"]]]
      ]
    edited["hooks"] = hooks
    let editedData = try JSONSerialization.data(withJSONObject: edited)

    let removed = try configuration.removing(from: editedData)
    let root = try jsonObject(removed)

    XCTAssertEqual(root["userAddedAfterConnect"] as? Bool, true)
    XCTAssertEqual(otherCommandCount(in: root, command: "/other"), 1)
    XCTAssertEqual(try configuration.ownedHandlerCount(in: removed), 0)
  }

  func testDisabledHooksAreReportedSeparately() throws {
    let configuration = ClaudeHookConfiguration()
    let installed = try configuration.installing(in: Data("{}".utf8), executableURL: executable)
    var root = try jsonObject(installed)
    root["disableAllHooks"] = true
    let disabled = try JSONSerialization.data(withJSONObject: root)

    XCTAssertEqual(
      try configuration.installationState(in: disabled, executableURL: executable),
      .connectedButDisabled
    )
  }

  func testMalformedHookStructureIsRejected() {
    let configuration = ClaudeHookConfiguration()
    let input = Data(#"{"hooks":{"Stop":"unexpected"}}"#.utf8)

    XCTAssertThrowsError(try configuration.installing(in: input, executableURL: executable)) {
      XCTAssertEqual($0 as? ClaudeHookConfigurationError, .invalidHookEvent("Stop"))
    }
  }

  func testMissingExecutableWrapperIsSilentAndSuccessful() throws {
    let handler = ClaudeHookConfiguration().handler(
      executableURL: URL(fileURLWithPath: "/missing/omapet")
    )
    let command = try XCTUnwrap(handler["command"] as? String)
    let arguments = try XCTUnwrap(handler["args"] as? [String])
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
    XCTAssertTrue(error.fileHandleForReading.readDataToEndOfFile().isEmpty)
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func otherCommandCount(in root: [String: Any], command: String) -> Int {
    guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
    return hooks.values.reduce(into: 0) { count, value in
      guard let groups = value as? [[String: Any]] else { return }
      for group in groups {
        guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
        count += handlers.count { $0["command"] as? String == command }
      }
    }
  }
}
