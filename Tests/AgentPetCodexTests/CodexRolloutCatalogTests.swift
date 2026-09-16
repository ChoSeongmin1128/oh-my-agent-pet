import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexRolloutCatalogTests: XCTestCase {
  func testUsesIndexOrderAndExcludesSubagentRollout() throws {
    let sessions = temporaryDirectory().appendingPathComponent("sessions")
    let day = sessions.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let first = uuid(1)
    let second = uuid(2)
    try Data().write(to: day.appendingPathComponent("rollout-2026-09-16T10-00-00-\(first).jsonl"))
    try Data().write(to: day.appendingPathComponent("rollout-2026-09-16T11-00-00-\(second).jsonl"))
    try Data().write(
      to: day.appendingPathComponent(
        "rollout-2026-09-16T10-00-00-\(first)_\(uuid(3)).jsonl"))
    let entries = [
      entry(id: second, title: "Second", seconds: 2),
      entry(id: first, title: "First", seconds: 1),
    ]

    let result = try CodexRolloutCatalog(
      sessionsDirectory: sessions,
      maximumSessions: 2
    ).discover(indexEntries: entries)

    XCTAssertEqual(result.candidates.map(\.sessionID), [second, first])
    XCTAssertEqual(result.candidates.map(\.title), ["Second", "First"])
    XCTAssertTrue(
      result.watchDirectories.map { $0.resolvingSymlinksInPath().path }
        .contains(day.resolvingSymlinksInPath().path),
      "watch directories: \(result.watchDirectories.map(\.path)); expected: \(day.path)"
    )
  }

  func testFallsBackToNewestRootRolloutWithoutIndex() throws {
    let sessions = temporaryDirectory().appendingPathComponent("sessions")
    let day = sessions.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let older = day.appendingPathComponent("rollout-2026-09-16T10-00-00-\(uuid(1)).jsonl")
    let newer = day.appendingPathComponent("rollout-2026-09-16T11-00-00-\(uuid(2)).jsonl")
    try Data().write(to: older)
    try Data().write(to: newer)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: older.path)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: newer.path)

    let result = try CodexRolloutCatalog(
      sessionsDirectory: sessions,
      maximumSessions: 1
    ).discover(indexEntries: [])

    XCTAssertEqual(result.candidates.map(\.sessionID), [uuid(2)])
  }

  func testIndexCanMatchNonUUIDSessionID() throws {
    let sessions = temporaryDirectory().appendingPathComponent("sessions")
    let day = sessions.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try Data().write(
      to: day.appendingPathComponent("rollout-2026-09-16T10-00-00-thr_example.jsonl"))

    let result = try CodexRolloutCatalog(
      sessionsDirectory: sessions,
      maximumSessions: 1
    ).discover(
      indexEntries: [entry(id: "thr_example", title: "Example", seconds: 1)])

    XCTAssertEqual(result.candidates.map(\.sessionID), ["thr_example"])
  }

  func testRejectsSymlinkSessionsDirectory() throws {
    let directory = temporaryDirectory()
    let target = directory.appendingPathComponent("target", isDirectory: true)
    let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: target)

    XCTAssertThrowsError(
      try CodexRolloutCatalog(
        sessionsDirectory: sessions,
        maximumSessions: 1
      ).discover(indexEntries: [])
    ) {
      XCTAssertEqual($0 as? CodexRolloutCatalogError, .unsafeDirectory)
    }
  }

  private func entry(id: String, title: String, seconds: TimeInterval) -> CodexSessionIndexEntry {
    CodexSessionIndexEntry(
      id: id,
      title: title,
      updatedAt: Date(timeIntervalSince1970: seconds)
    )
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
