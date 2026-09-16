import AgentPetEvents
import Foundation
import XCTest

final class AgentHookEventTests: XCTestCase {
  func testCodexRecorderStoresProviderAndTurnWithoutSensitivePayload() throws {
    let directory = temporaryDirectory()
    let recorder = AgentHookRecorder(provider: .codex, applicationSupportDirectory: directory)
    let secret = "PRIVATE_PROMPT_AND_COMMAND"
    let payload = Data(
      """
      {
        "hook_event_name": "PermissionRequest",
        "session_id": "session-1",
        "turn_id": "turn-1",
        "cwd": "/tmp/project",
        "tool_name": "Bash",
        "transcript_path": "/tmp/transcript.jsonl",
        "prompt": "\(secret)",
        "tool_input": {"command": "\(secret)"}
      }
      """.utf8
    )

    XCTAssertEqual(
      try recorder.record(
        input: payload,
        now: Date(timeIntervalSince1970: 1),
        recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
      ),
      .recorded
    )
    let data = try Data(contentsOf: recorder.eventsURL)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secret))
    let event = try JSONDecoder().decode(
      StoredAgentHookEvent.self,
      from: Data(data.dropLast())
    )
    XCTAssertEqual(event.provider, .codex)
    XCTAssertEqual(event.turnID, "turn-1")
    XCTAssertEqual(event.hookEventName, "PermissionRequest")
    XCTAssertEqual(event.toolName, "Bash")
  }

  func testSchemaOneRecordDefaultsToClaudeForMigration() throws {
    let data = Data(
      #"{"schema_version":1,"record_id":"00000000-0000-0000-0000-000000000001","received_at_ms":1000,"hook_event_name":"Stop","session_id":"session","cwd":"/tmp"}"#
        .utf8
    )

    let event = try JSONDecoder().decode(StoredAgentHookEvent.self, from: data)

    XCTAssertEqual(event.schemaVersion, 1)
    XCTAssertEqual(event.provider, .claude)
    XCTAssertNil(event.turnID)
  }

  func testSchemaTwoRequiresExplicitProvider() {
    let data = Data(
      #"{"schema_version":2,"record_id":"00000000-0000-0000-0000-000000000001","received_at_ms":1000,"hook_event_name":"Stop","session_id":"session","cwd":"/tmp"}"#
        .utf8
    )

    XCTAssertThrowsError(try JSONDecoder().decode(StoredAgentHookEvent.self, from: data))
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
