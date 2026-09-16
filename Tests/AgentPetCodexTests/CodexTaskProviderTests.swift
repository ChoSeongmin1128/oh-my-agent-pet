import AgentPetCodex
import AgentPetCore
import Foundation
import XCTest

final class CodexTaskProviderTests: XCTestCase {
  func testMissingCodexDataReturnsEmptyTasks() async throws {
    let home = temporaryDirectory()
    let provider = CodexTaskProvider(
      paths: CodexPaths(homeDirectory: home, environment: [:]))

    let tasks = try await provider.loadTasks()

    XCTAssertEqual(tasks, [])
  }

  func testLoadsRecentIndexedSessionsWithProviderIdentity() async throws {
    let home = temporaryDirectory()
    let paths = CodexPaths(homeDirectory: home, environment: [:])
    let day = paths.sessionsDirectory.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try index([
      (uuid(2), "Second", 2),
      (uuid(1), "First", 1),
    ]).write(to: paths.sessionIndexURL)
    try rollout(session: 1, state: "task_complete").write(
      to: rolloutURL(day: day, session: 1))
    try rollout(session: 2, state: "task_started").write(
      to: rolloutURL(day: day, session: 2))
    let provider = CodexTaskProvider(paths: paths, maximumSessions: 2)

    let tasks = try await provider.loadTasks()

    XCTAssertEqual(Set(tasks.map(\.title)), Set(["First", "Second"]))
    XCTAssertTrue(tasks.allSatisfy { $0.identity.provider == ProviderIdentifier("codex")! })
    XCTAssertEqual(tasks.first(where: { $0.title == "Second" })?.work, .running)
    XCTAssertFalse(tasks.first(where: { $0.title == "First" })?.hasUnseenCompletion == true)
  }

  func testLiveCompletionBecomesUnseenAndWatchListIncludesRollout() async throws {
    let home = temporaryDirectory()
    let paths = CodexPaths(homeDirectory: home, environment: [:])
    let day = paths.sessionsDirectory.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try index([(uuid(1), "Task", 1)]).write(to: paths.sessionIndexURL)
    let url = rolloutURL(day: day, session: 1)
    try rollout(session: 1, state: "task_started").write(to: url)
    let provider = CodexTaskProvider(paths: paths)
    _ = try await provider.loadTasks()

    try append(lifecycle("task_complete", turn: "turn-1", second: 3), to: url)
    let task = try await provider.loadTasks().first
    let watched = await provider.watchedURLs()

    XCTAssertEqual(task?.result, .completed)
    XCTAssertTrue(task?.hasUnseenCompletion == true)
    XCTAssertTrue(
      watched.map { $0.resolvingSymlinksInPath().path }
        .contains(url.resolvingSymlinksInPath().path),
      "watched: \(watched.map(\.path)); expected: \(url.path)"
    )
    XCTAssertTrue(watched.map(\.path).contains(paths.sessionIndexURL.path))
  }

  func testFallsBackToRolloutWhenIndexIsMissing() async throws {
    let home = temporaryDirectory()
    let paths = CodexPaths(homeDirectory: home, environment: [:])
    let day = paths.sessionsDirectory.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try rollout(session: 1, state: "task_started").write(
      to: rolloutURL(day: day, session: 1))
    let provider = CodexTaskProvider(paths: paths)

    let task = try await provider.loadTasks().first

    XCTAssertEqual(task?.title, "project-1")
    XCTAssertEqual(task?.work, .running)
  }

  func testIndexChangeDiscoversNewSessionAndHonorsLimit() async throws {
    let home = temporaryDirectory()
    let paths = CodexPaths(homeDirectory: home, environment: [:])
    let day = paths.sessionsDirectory.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try index([(uuid(1), "First", 1)]).write(to: paths.sessionIndexURL)
    try rollout(session: 1, state: "task_started").write(
      to: rolloutURL(day: day, session: 1))
    let provider = CodexTaskProvider(paths: paths, maximumSessions: 1)
    let initial = try await provider.loadTasks()
    XCTAssertEqual(initial.map(\.title), ["First"])

    try rollout(session: 2, state: "task_started").write(
      to: rolloutURL(day: day, session: 2))
    try index([
      (uuid(1), "First", 1),
      (uuid(2), "Second", 2),
    ]).write(to: paths.sessionIndexURL, options: .atomic)
    let tasks = try await provider.loadTasks()

    XCTAssertEqual(tasks.map(\.title), ["Second"])
  }

  func testIndexTitleUpdateReusesTrackedRollout() async throws {
    let home = temporaryDirectory()
    let paths = CodexPaths(homeDirectory: home, environment: [:])
    let day = paths.sessionsDirectory.appendingPathComponent("2026/09/16", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    try index([(uuid(1), "Before", 1)]).write(to: paths.sessionIndexURL)
    try rollout(session: 1, state: "task_started").write(
      to: rolloutURL(day: day, session: 1))
    let provider = CodexTaskProvider(paths: paths, maximumSessions: 1)
    _ = try await provider.loadTasks()

    try index([(uuid(1), "After", 2)]).write(to: paths.sessionIndexURL, options: .atomic)
    let tasks = try await provider.loadTasks()

    XCTAssertEqual(tasks.map(\.title), ["After"])
  }

  private func index(_ rows: [(String, String, Int)]) -> Data {
    rows.reduce(into: Data()) { data, row in
      data.append(
        Data(
          "{\"id\":\"\(row.0)\",\"thread_name\":\"\(row.1)\",\"updated_at\":\"2026-09-16T10:00:\(String(format: "%02d", row.2))Z\"}\n"
            .utf8
        ))
    }
  }

  private func rollout(session: Int, state: String) -> Data {
    var data = Data(
      "{\"timestamp\":\"2026-09-16T10:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(uuid(session))\",\"cwd\":\"/tmp/project-\(session)\"}}\n"
        .utf8
    )
    data.append(lifecycle("task_started", turn: "turn-\(session)", second: 1))
    if state != "task_started" {
      data.append(lifecycle(state, turn: "turn-\(session)", second: 2))
    }
    return data
  }

  private func lifecycle(_ type: String, turn: String, second: Int) -> Data {
    Data(
      "{\"timestamp\":\"2026-09-16T10:00:\(String(format: "%02d", second))Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turn)\"}}\n"
        .utf8
    )
  }

  private func rolloutURL(day: URL, session: Int) -> URL {
    day.appendingPathComponent(
      "rollout-2026-09-16T10-00-00-\(uuid(session)).jsonl")
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
