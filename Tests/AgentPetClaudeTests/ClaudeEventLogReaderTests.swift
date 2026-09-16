import AgentPetClaude
import Foundation
import XCTest

final class ClaudeEventLogReaderTests: XCTestCase {
  func testMissingFileIsAnEmptyCompleteBatch() throws {
    var reader = ClaudeEventLogReader(
      eventsURL: temporaryDirectory().appendingPathComponent("events"))

    let batch = try reader.readAvailable()

    XCTAssertEqual(batch.events, [])
    XCTAssertEqual(batch.issues, [])
    XCTAssertFalse(batch.didReset)
    XCTAssertTrue(batch.reachedEnd)
  }

  func testReadsOnlyAppendedCompleteRecords() throws {
    let url = temporaryDirectory().appendingPathComponent("events.ndjson")
    let first = event(id: 1, name: "UserPromptSubmit")
    let second = event(id: 2, name: "Stop")
    try line(first).write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)

    XCTAssertEqual(try reader.readAvailable().events, [first])
    try append(line(second), to: url)

    XCTAssertEqual(try reader.readAvailable().events, [second])
  }

  func testWaitsForNewlineBeforePublishingPartialRecord() throws {
    let url = temporaryDirectory().appendingPathComponent("events.ndjson")
    let stored = event(id: 1, name: "Stop")
    let data = try JSONEncoder().encode(stored)
    try data.write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)

    XCTAssertEqual(try reader.readAvailable().events, [])
    try append(Data([0x0A]), to: url)

    XCTAssertEqual(try reader.readAvailable().events, [stored])
  }

  func testSkipsInvalidAndUnsupportedRecords() throws {
    let url = temporaryDirectory().appendingPathComponent("events.ndjson")
    var data = Data("not-json\n".utf8)
    let supported = String(decoding: try line(event(id: 1, name: "Stop")), as: UTF8.self)
    data.append(
      Data(
        supported.replacingOccurrences(of: "\"schema_version\":3", with: "\"schema_version\":99")
          .utf8))
    try data.write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)

    let batch = try reader.readAvailable()

    XCTAssertEqual(batch.events, [])
    XCTAssertEqual(batch.issues, [.invalidRecord, .unsupportedSchema])
  }

  func testReportsOversizedRecordOnceAndContinuesAtNextLine() throws {
    let url = temporaryDirectory().appendingPathComponent("events.ndjson")
    let stored = event(id: 2, name: "Stop")
    var data = Data(repeating: 0x61, count: ClaudeEventLogReader.maximumRecordBytes + 10)
    data.append(0x0A)
    data.append(try line(stored))
    try data.write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)

    var issues: [ClaudeEventLogIssue] = []
    var events: [StoredClaudeHookEvent] = []
    while true {
      let batch = try reader.readAvailable(maximumBytes: 4_096)
      issues.append(contentsOf: batch.issues)
      events.append(contentsOf: batch.events)
      if batch.reachedEnd { break }
    }

    XCTAssertEqual(issues, [.oversizedRecord])
    XCTAssertEqual(events, [stored])
  }

  func testResetsAfterTruncation() throws {
    let url = temporaryDirectory().appendingPathComponent("events.ndjson")
    let first = event(id: 1, name: "UserPromptSubmit", cwd: "/a/very-long-project-name")
    let second = event(id: 2, name: "Stop", cwd: "/x")
    try line(first).write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)
    _ = try reader.readAvailable()

    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: line(second))
    try handle.close()
    let batch = try reader.readAvailable()

    XCTAssertTrue(batch.didReset)
    XCTAssertEqual(batch.events, [second])
  }

  func testResetsAfterFileReplacement() throws {
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("events.ndjson")
    let replacement = directory.appendingPathComponent("replacement")
    let first = event(id: 1, name: "UserPromptSubmit")
    let second = event(id: 2, name: "Stop")
    try line(first).write(to: url)
    var reader = ClaudeEventLogReader(eventsURL: url)
    _ = try reader.readAvailable()

    try line(second).write(to: replacement)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: replacement, to: url)
    let batch = try reader.readAvailable()

    XCTAssertTrue(batch.didReset)
    XCTAssertEqual(batch.events, [second])
  }

  func testRejectsSymbolicLink() throws {
    let directory = temporaryDirectory()
    let target = directory.appendingPathComponent("target")
    let link = directory.appendingPathComponent("events.ndjson")
    try Data().write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    var reader = ClaudeEventLogReader(eventsURL: link)

    XCTAssertThrowsError(try reader.readAvailable()) {
      XCTAssertEqual($0 as? ClaudeEventLogReaderError, .unsafeFile)
    }
  }

  private func event(
    id: Int,
    name: String,
    cwd: String = "/tmp/project"
  ) -> StoredClaudeHookEvent {
    StoredClaudeHookEvent(
      recordID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
      receivedAtMilliseconds: Int64(id * 1_000),
      hookEventName: name,
      sessionID: "session",
      cwd: cwd,
      source: nil,
      notificationType: nil,
      toolName: nil
    )
  }

  private func line(_ event: StoredClaudeHookEvent) throws -> Data {
    var data = try JSONEncoder().encode(event)
    data.append(0x0A)
    return data
  }

  private func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.close()
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
