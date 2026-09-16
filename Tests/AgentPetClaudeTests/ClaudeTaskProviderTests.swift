import AgentPetClaude
import XCTest

final class ClaudeTaskProviderTests: XCTestCase {
  func testReplaysThenLoadsOnlyNewEvents() async throws {
    let home = temporaryDirectory()
    let paths = ClaudePaths(homeDirectory: home, environment: [:])
    try FileManager.default.createDirectory(
      at: paths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    let prompt = event(id: 1, name: "UserPromptSubmit")
    try line(prompt).write(to: paths.eventsURL)
    let provider = ClaudeTaskProvider(paths: paths)

    let running = try await provider.loadTasks().first
    XCTAssertEqual(running?.work, .running)
    try append(line(event(id: 2, name: "Stop")), to: paths.eventsURL)
    let completed = try await provider.loadTasks().first

    XCTAssertEqual(completed?.result, .completed)
    XCTAssertTrue(completed?.hasUnseenCompletion == true)
  }

  func testMalformedRecordDoesNotPreventLaterValidRecord() async throws {
    let home = temporaryDirectory()
    let paths = ClaudePaths(homeDirectory: home, environment: [:])
    try FileManager.default.createDirectory(
      at: paths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    var data = Data("broken\n".utf8)
    data.append(try line(event(id: 1, name: "SessionStart")))
    try data.write(to: paths.eventsURL)
    let provider = ClaudeTaskProvider(paths: paths)

    let tasks = try await provider.loadTasks()

    XCTAssertEqual(tasks.count, 1)
    let issues = await provider.currentIssues()
    XCTAssertEqual(issues, [.invalidRecord])
  }

  func testRetainsOnlyRecentReaderIssues() async throws {
    let home = temporaryDirectory()
    let paths = ClaudePaths(homeDirectory: home, environment: [:])
    try FileManager.default.createDirectory(
      at: paths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    let data = Data(Array(repeating: "broken\n", count: 200).joined().utf8)
    try data.write(to: paths.eventsURL)
    let provider = ClaudeTaskProvider(paths: paths)

    _ = try await provider.loadTasks()
    let issues = await provider.currentIssues()

    XCTAssertEqual(issues.count, 128)
  }

  func testFileReplacementRebuildsStateInsteadOfMerging() async throws {
    let home = temporaryDirectory()
    let paths = ClaudePaths(homeDirectory: home, environment: [:])
    try FileManager.default.createDirectory(
      at: paths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    try line(event(id: 1, name: "UserPromptSubmit", sessionID: "old")).write(
      to: paths.eventsURL)
    let provider = ClaudeTaskProvider(paths: paths)
    let initial = try await provider.loadTasks()
    XCTAssertEqual(initial.map(\.identity.taskID), ["old"])

    let replacement = paths.applicationSupportDirectory.appendingPathComponent("replacement")
    try line(event(id: 2, name: "SessionStart", sessionID: "new")).write(to: replacement)
    try FileManager.default.removeItem(at: paths.eventsURL)
    try FileManager.default.moveItem(at: replacement, to: paths.eventsURL)
    let rebuilt = try await provider.loadTasks()

    XCTAssertEqual(rebuilt.map(\.identity.taskID), ["new"])
  }

  func testDesktopIndexAddsExactClaudeDeepLink() async throws {
    let home = temporaryDirectory()
    let paths = ClaudePaths(homeDirectory: home, environment: [:])
    try FileManager.default.createDirectory(
      at: paths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: paths.desktopSessionsDirectory,
      withIntermediateDirectories: true
    )
    let cliID = "11111111-1111-1111-1111-111111111111"
    try line(event(id: 1, name: "SessionStart", sessionID: cliID)).write(
      to: paths.eventsURL
    )
    try Data(
      """
      {"sessionId":"local_22222222-2222-2222-2222-222222222222","cliSessionId":"\(cliID)","isArchived":false,"lastActivityAt":10}
      """.utf8
    ).write(to: paths.desktopSessionsDirectory.appendingPathComponent("route.json"))
    let provider = ClaudeTaskProvider(paths: paths)

    let target = try await provider.loadTasks().first?.navigationTarget

    XCTAssertEqual(target?.surface, .desktop)
    XCTAssertEqual(target?.applicationBundleIdentifier, "com.anthropic.claudefordesktop")
    XCTAssertEqual(
      target?.deepLink,
      "claude://code/continue?session=local_22222222-2222-2222-2222-222222222222"
    )
  }

  private func event(
    id: Int,
    name: String,
    sessionID: String = "session"
  ) -> StoredClaudeHookEvent {
    StoredClaudeHookEvent(
      recordID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
      receivedAtMilliseconds: Int64(id * 1_000),
      hookEventName: name,
      sessionID: sessionID,
      cwd: "/tmp/project",
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
