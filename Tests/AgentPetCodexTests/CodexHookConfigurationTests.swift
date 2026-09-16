import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexHookConfigurationTests: XCTestCase {
  func testInstallPreservesDescriptionAndExistingHooks() throws {
    let configuration = CodexHookConfiguration()
    let executable = URL(fileURLWithPath: "/Applications/Oh My Agent Pet.app/Contents/MacOS/omapet")
    let source = Data(
      #"{"description":"keep","hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"other"}]}]}}"#
        .utf8
    )

    let installed = try configuration.installing(in: source, executableURL: executable)
    let root = try object(installed)
    let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])

    XCTAssertEqual(root["description"] as? String, "keep")
    XCTAssertNotNil(hooks["PreCompact"])
    XCTAssertEqual(
      try configuration.ownedHandlerCount(in: installed),
      CodexHookConfiguration.eventNames.count
    )
    XCTAssertEqual(
      try configuration.installationState(in: installed, executableURL: executable),
      .needsTrust
    )
  }

  func testInstallIsIdempotentAndQuotesApostropheInExecutablePath() throws {
    let configuration = CodexHookConfiguration()
    let executable = URL(fileURLWithPath: "/tmp/O'Mapet App/omapet")

    let first = try configuration.installing(in: Data("{}".utf8), executableURL: executable)
    let second = try configuration.installing(in: first, executableURL: executable)
    let command = configuration.command(executableURL: executable)

    XCTAssertEqual(first, second)
    XCTAssertTrue(command.contains("'\"'\"'"))
    XCTAssertTrue(command.hasSuffix(" hook codex >/dev/null 2>/dev/null || :"))
  }

  func testRemoveDropsOnlyOwnedHandlers() throws {
    let configuration = CodexHookConfiguration()
    let executable = URL(fileURLWithPath: "/tmp/omapet")
    let installed = try configuration.installing(
      in: Data(#"{"description":"keep"}"#.utf8),
      executableURL: executable
    )
    var root = try object(installed)
    var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
    hooks["SessionStart"] =
      (hooks["SessionStart"] as! [[String: Any]]) + [
        ["hooks": [["type": "command", "command": "other"]]]
      ]
    root["hooks"] = hooks
    let edited = try JSONSerialization.data(withJSONObject: root)

    let removed = try configuration.removing(from: edited)
    let removedRoot = try object(removed)
    let remainingHooks = try XCTUnwrap(removedRoot["hooks"] as? [String: Any])

    XCTAssertEqual(try configuration.ownedHandlerCount(in: removed), 0)
    XCTAssertNotNil(remainingHooks["SessionStart"])
    XCTAssertEqual(removedRoot["description"] as? String, "keep")
  }

  func testMalformedHookStructureIsRejected() {
    let configuration = CodexHookConfiguration()
    XCTAssertThrowsError(
      try configuration.installing(
        in: Data(#"{"hooks":{"Stop":true}}"#.utf8),
        executableURL: URL(fileURLWithPath: "/tmp/omapet")
      )
    ) {
      XCTAssertEqual($0 as? CodexHookConfigurationError, .invalidHookEvent("Stop"))
    }
  }

  func testMissingExecutableCommandIsSilentAndSuccessful() throws {
    let command = CodexHookConfiguration().command(
      executableURL: URL(fileURLWithPath: "/tmp/Missing O'Mapet/omapet")
    )
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data())
    XCTAssertEqual(error.fileHandleForReading.readDataToEndOfFile(), Data())
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
