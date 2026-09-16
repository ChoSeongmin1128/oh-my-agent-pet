import AgentPetClaude
import AgentPetCore
import XCTest

final class ClaudeEventReducerTests: XCTestCase {
  func testPromptPermissionToolAndStopLifecycle() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")

    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    XCTAssertEqual(reducer.snapshots.first?.work, .running)
    reducer.apply(event(id: 2, name: "PermissionRequest"))
    XCTAssertEqual(reducer.snapshots.first?.waiting, .user(.approval))
    reducer.apply(event(id: 3, name: "PreToolUse"))
    XCTAssertEqual(reducer.snapshots.first?.waiting, WaitingState.none)
    reducer.apply(event(id: 4, name: "Stop"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.work, .stopped)
    XCTAssertEqual(snapshot.result, .completed)
    XCTAssertEqual(snapshot.waiting, .none)
    XCTAssertTrue(snapshot.hasUnseenCompletion)
  }

  func testToolFailureDoesNotMarkTaskFailed() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    reducer.apply(event(id: 2, name: "PostToolUseFailure"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.work, .running)
    XCTAssertEqual(snapshot.result, .none)
    XCTAssertEqual(snapshot.waiting, .none)
  }

  func testStopFailureIsAnActionableUnseenFailure() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    reducer.apply(event(id: 2, name: "StopFailure"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.work, .stopped)
    XCTAssertEqual(snapshot.result, .failed)
    XCTAssertEqual(snapshot.waiting, .user(.actionableFailure))
    XCTAssertTrue(snapshot.hasUnseenCompletion)
  }

  func testSessionEndUsesUnknownWhenNoResultExists() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "SessionStart"))
    reducer.apply(event(id: 2, name: "SessionEnd"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.work, .stopped)
    XCTAssertEqual(snapshot.result, .unknown)
  }

  func testSessionEndKeepsCompletedUnseenResult() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    reducer.apply(event(id: 2, name: "Stop"))
    reducer.apply(event(id: 3, name: "SessionEnd"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.work, .stopped)
    XCTAssertEqual(snapshot.result, .completed)
    XCTAssertTrue(snapshot.hasUnseenCompletion)
  }

  func testNewPromptStartsNewTurnAndClearsCompletion() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    reducer.apply(event(id: 2, name: "Stop"))
    reducer.apply(event(id: 3, name: "UserPromptSubmit"))

    let snapshot = try XCTUnwrap(reducer.snapshots.first)
    XCTAssertEqual(snapshot.result, .none)
    XCTAssertFalse(snapshot.hasUnseenCompletion)
    XCTAssertEqual(
      snapshot.identity.turnID,
      event(id: 3, name: "UserPromptSubmit").recordID.uuidString.lowercased())
  }

  func testDuplicateRecordIsIgnored() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    let prompt = event(id: 1, name: "UserPromptSubmit")
    reducer.apply(prompt)
    reducer.apply(event(id: 2, name: "Stop"))
    reducer.apply(prompt)

    XCTAssertEqual(reducer.snapshots.first?.result, .completed)
  }

  func testNotificationCanRequestInput() throws {
    var reducer = ClaudeEventReducer(dataRoot: "/fixture")
    reducer.apply(event(id: 1, name: "UserPromptSubmit"))
    reducer.apply(event(id: 2, name: "Notification", notificationType: "agent_needs_input"))

    XCTAssertEqual(reducer.snapshots.first?.waiting, .user(.answer))
  }

  private func event(
    id: Int,
    name: String,
    notificationType: String? = nil
  ) -> StoredClaudeHookEvent {
    StoredClaudeHookEvent(
      recordID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
      receivedAtMilliseconds: Int64(id * 1_000),
      hookEventName: name,
      sessionID: "session",
      cwd: "/tmp/project",
      source: nil,
      notificationType: notificationType,
      toolName: nil
    )
  }
}
