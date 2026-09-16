import AgentPetCore
import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexRolloutTrackerTests: XCTestCase {
  func testInitialRunningTurnUsesIndexTitleWithoutUnseenResult() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url, title: "Indexed title")

    let refresh = tracker.refresh()

    XCTAssertEqual(refresh.snapshot?.title, "Indexed title")
    XCTAssertEqual(refresh.snapshot?.work, .running)
    XCTAssertEqual(refresh.snapshot?.result, ResultState.none)
    XCTAssertEqual(refresh.snapshot?.identity.turnID, "turn-1")
    XCTAssertFalse(refresh.snapshot?.hasUnseenCompletion == true)
  }

  func testHistoricalCompletionIsNotMarkedUnseen() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([
      metadata(),
      lifecycle("task_started", turn: "turn-1", second: 1),
      lifecycle("task_complete", turn: "turn-1", second: 2),
    ]).write(to: url)
    var tracker = makeTracker(url: url)

    let snapshot = tracker.refresh().snapshot

    XCTAssertEqual(snapshot?.result, .completed)
    XCTAssertEqual(snapshot?.identity.turnID, "turn-1")
    XCTAssertFalse(snapshot?.hasUnseenCompletion == true)
  }

  func testLiveCompletionBecomesUnseen() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url)
    _ = tracker.refresh()

    try append(lifecycle("task_complete", turn: "turn-1", second: 2), to: url)
    let snapshot = tracker.refresh().snapshot

    XCTAssertEqual(snapshot?.work, .stopped)
    XCTAssertEqual(snapshot?.result, .completed)
    XCTAssertTrue(snapshot?.hasUnseenCompletion == true)
  }

  func testPartialLifecycleWaitsForNewline() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url)
    _ = tracker.refresh()
    let completion = lifecycle("task_complete", turn: "turn-1", second: 2)
    try append(Data(completion.dropLast()), to: url)

    XCTAssertEqual(tracker.refresh().snapshot?.work, .running)
    try append(Data([0x0A]), to: url)

    XCTAssertEqual(tracker.refresh().snapshot?.result, .completed)
  }

  func testLateCompletionFromPreviousTurnDoesNotStopCurrentTurn() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url)
    _ = tracker.refresh()

    try append(lifecycle("task_started", turn: "turn-2", second: 2), to: url)
    try append(lifecycle("task_complete", turn: "turn-1", second: 3), to: url)
    let snapshot = tracker.refresh().snapshot

    XCTAssertEqual(snapshot?.work, .running)
    XCTAssertEqual(snapshot?.identity.turnID, "turn-2")
  }

  func testTurnAbortedIsInterruptedInsteadOfCompletedOrFailed() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url)
    _ = tracker.refresh()

    try append(lifecycle("turn_aborted", turn: "turn-1", second: 2), to: url)
    let snapshot = tracker.refresh().snapshot

    XCTAssertEqual(snapshot?.work, .stopped)
    XCTAssertEqual(snapshot?.result, .interrupted)
    XCTAssertFalse(snapshot?.hasUnseenCompletion == true)
  }

  func testFileReplacementRebuildsWithoutNewCompletion() throws {
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("rollout.jsonl")
    try rollout([metadata(), lifecycle("task_started", turn: "turn-1", second: 1)]).write(to: url)
    var tracker = makeTracker(url: url)
    _ = tracker.refresh()
    let replacement = directory.appendingPathComponent("replacement")
    try rollout([
      metadata(),
      lifecycle("task_started", turn: "turn-2", second: 2),
      lifecycle("task_complete", turn: "turn-2", second: 3),
    ]).write(to: replacement)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: replacement, to: url)

    let refresh = tracker.refresh()

    XCTAssertTrue(refresh.didReset)
    XCTAssertEqual(refresh.snapshot?.result, .completed)
    XCTAssertFalse(refresh.snapshot?.hasUnseenCompletion == true)
  }

  func testRejectsSymbolicLink() throws {
    let directory = temporaryDirectory()
    let target = directory.appendingPathComponent("target")
    let link = directory.appendingPathComponent("rollout.jsonl")
    try rollout([metadata()]).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    var tracker = makeTracker(url: link)

    XCTAssertEqual(tracker.refresh().issues, [.unsafeFile])
  }

  func testIgnoresPromptTextContainingLifecycleWords() throws {
    let url = temporaryDirectory().appendingPathComponent("rollout.jsonl")
    try rollout([
      metadata(),
      lifecycle("task_started", turn: "turn-1", second: 1),
      Data(
        "{\"timestamp\":\"2026-09-16T10:00:02Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"text\":\"task_complete\"}}\n"
          .utf8
      ),
    ]).write(to: url)
    var tracker = makeTracker(url: url)

    let refresh = tracker.refresh()

    XCTAssertEqual(refresh.snapshot?.work, .running)
    XCTAssertEqual(refresh.issues, [])
  }

  private func makeTracker(
    url: URL,
    title: String? = nil
  ) -> CodexRolloutTracker {
    CodexRolloutTracker(
      candidate: CodexRolloutCandidate(
        sessionID: uuid(1),
        title: title,
        indexUpdatedAt: Date(timeIntervalSince1970: 1),
        rolloutURL: url
      ),
      dataRoot: "/fixture/.codex"
    )
  }

  private func metadata() -> Data {
    Data(
      "{\"timestamp\":\"2026-09-16T10:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(uuid(1))\",\"cwd\":\"/tmp/project\",\"base_instructions\":\"private\"}}\n"
        .utf8
    )
  }

  private func lifecycle(_ type: String, turn: String, second: Int) -> Data {
    Data(
      "{\"timestamp\":\"2026-09-16T10:00:\(String(format: "%02d", second))Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turn)\",\"last_agent_message\":\"private response\"}}\n"
        .utf8
    )
  }

  private func rollout(_ lines: [Data]) -> Data {
    lines.reduce(into: Data()) { $0.append($1) }
  }

  private func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.close()
  }

  private func uuid(_ value: Int) -> String {
    String(format: "00000000-0000-0000-0000-%012d", value)
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
