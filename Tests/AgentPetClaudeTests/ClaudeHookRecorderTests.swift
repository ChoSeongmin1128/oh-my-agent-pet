import AgentPetClaude
import AgentPetEvents
import Foundation
import XCTest

final class ClaudeHookRecorderTests: XCTestCase {
  func testRecordStoresOnlyAllowedFieldsWithSecurePermissions() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)
    let secret = "SECRET_PROMPT_AND_TOOL_INPUT"
    let payload = Data(
      """
      {
        "hook_event_name": "PreToolUse",
        "session_id": "session-1",
        "cwd": "/tmp/project",
        "transcript_path": "/tmp/private-transcript.jsonl",
        "permission_mode": "default",
        "tool_name": "Bash",
        "prompt": "\(secret)",
        "tool_input": {"command": "\(secret)"},
        "tool_output": "\(secret)",
        "message": "\(secret)",
        "error_details": "\(secret)"
      }
      """.utf8
    )

    let result = try recorder.record(
      input: payload,
      now: Date(timeIntervalSince1970: 1_000),
      recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      environment: [:],
      tty: nil
    )
    let storedData = try Data(contentsOf: recorder.eventsURL)
    let line = try XCTUnwrap(String(data: storedData, encoding: .utf8))
    let event = try JSONDecoder().decode(
      StoredClaudeHookEvent.self,
      from: Data(line.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    )
    let storedObject = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: Data(line.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
      ) as? [String: Any]
    )
    let attributes = try FileManager.default.attributesOfItem(atPath: recorder.eventsURL.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value

    XCTAssertEqual(result, .recorded)
    XCTAssertFalse(line.contains(secret))
    XCTAssertEqual(event.hookEventName, "PreToolUse")
    XCTAssertEqual(event.sessionID, "session-1")
    XCTAssertEqual(event.cwd, "/tmp/project")
    XCTAssertEqual(event.toolName, "Bash")
    XCTAssertEqual(event.receivedAtMilliseconds, 1_000_000)
    XCTAssertEqual(permissions, 0o600)
    XCTAssertEqual(
      Set(storedObject.keys),
      [
        "schema_version",
        "provider",
        "record_id",
        "received_at_ms",
        "hook_event_name",
        "session_id",
        "cwd",
        "tool_name",
      ]
    )
  }

  func testUnsupportedEventIsIgnoredWithoutCreatingFile() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)
    let payload = Data(
      #"{"hook_event_name":"UnknownFutureEvent","session_id":"s","cwd":"/tmp"}"#.utf8
    )

    XCTAssertEqual(try recorder.record(input: payload), .ignored)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.eventsURL.path))
  }

  func testInvalidJSONAndOversizedPayloadAreRejected() {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)

    XCTAssertThrowsError(try recorder.record(input: Data("{".utf8))) {
      XCTAssertEqual($0 as? ClaudeHookRecorderError, .invalidJSON)
    }
    XCTAssertThrowsError(
      try recorder.record(input: Data(count: ClaudeHookRecorder.maximumInputBytes + 1))
    ) {
      XCTAssertEqual($0 as? ClaudeHookRecorderError, .inputTooLarge)
    }
  }

  func testSymlinkStorageTargetIsRejected() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("target")
    try Data().write(to: target)
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)
    try FileManager.default.createSymbolicLink(at: recorder.eventsURL, withDestinationURL: target)
    let payload = Data(
      #"{"hook_event_name":"Stop","session_id":"s","cwd":"/tmp"}"#.utf8
    )

    XCTAssertThrowsError(try recorder.record(input: payload)) {
      XCTAssertEqual($0 as? ClaudeHookRecorderError, .unsafeStorageTarget)
    }
  }

  func testConcurrentAppendsProduceCompleteJSONLines() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<50 {
        group.addTask {
          let payload = Data(
            """
            {"hook_event_name":"PostToolUse","session_id":"session-\(index)","cwd":"/tmp"}
            """.utf8
          )
          _ = try recorder.record(input: payload)
        }
      }
      try await group.waitForAll()
    }

    let data = try Data(contentsOf: recorder.eventsURL)
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    let events = try lines.map {
      try JSONDecoder().decode(StoredClaudeHookEvent.self, from: Data($0.utf8))
    }

    XCTAssertEqual(events.count, 50)
    XCTAssertEqual(Set(events.map(\.sessionID)).count, 50)
  }

  func testEventLogRotatesUnderExclusiveWriterLock() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)
    try Data(repeating: 0x20, count: ClaudeHookRecorder.maximumEventLogBytes)
      .write(to: recorder.eventsURL)
    let payload = Data(
      #"{"hook_event_name":"Stop","session_id":"rotated","cwd":"/tmp"}"#.utf8
    )

    _ = try recorder.record(input: payload)

    let rotatedURL = directory.appendingPathComponent("events.ndjson.1")
    XCTAssertEqual(
      try Data(contentsOf: rotatedURL).count,
      ClaudeHookRecorder.maximumEventLogBytes
    )
    let current = try String(contentsOf: recorder.eventsURL, encoding: .utf8)
    XCTAssertTrue(current.contains(#""session_id":"rotated""#))
    let lockAttributes = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent(".events.lock").path
    )
    XCTAssertEqual(
      (lockAttributes[.posixPermissions] as? NSNumber)?.uint16Value,
      0o600
    )
  }

  func testRotationRefusesUnexpectedArchiveDirectory() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recorder = ClaudeHookRecorder(applicationSupportDirectory: directory)
    try Data(repeating: 0x20, count: ClaudeHookRecorder.maximumEventLogBytes)
      .write(to: recorder.eventsURL)
    let archiveDirectory = directory.appendingPathComponent("events.ndjson.1", isDirectory: true)
    try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: archiveDirectory.appendingPathComponent("sentinel"))
    let payload = Data(
      #"{"hook_event_name":"Stop","session_id":"rotate-safe","cwd":"/tmp"}"#.utf8
    )

    XCTAssertThrowsError(try recorder.record(input: payload)) {
      XCTAssertEqual($0 as? AgentHookRecorderError, .unsafeStorageTarget)
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: archiveDirectory.appendingPathComponent("sentinel").path)
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }
}
