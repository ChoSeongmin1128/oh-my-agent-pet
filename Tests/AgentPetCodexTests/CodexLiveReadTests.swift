import AgentPetCodex
import Foundation
import XCTest

final class CodexLiveReadTests: XCTestCase {
  func testConfiguredLiveRootWhenRequested() async throws {
    guard let root = ProcessInfo.processInfo.environment["OMAPET_LIVE_CODEX_ROOT"] else {
      throw XCTSkip("Set OMAPET_LIVE_CODEX_ROOT for the read-only local format check.")
    }
    let paths = CodexPaths(
      homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
      environment: ["CODEX_HOME": root]
    )
    let provider = CodexTaskProvider(paths: paths)
    let startedAt = ContinuousClock.now

    let tasks = try await provider.loadTasks()
    let initialElapsed = startedAt.duration(to: .now)
    let refreshStartedAt = ContinuousClock.now
    _ = try await provider.loadTasks()
    let refreshElapsed = refreshStartedAt.duration(to: .now)

    XCTAssertFalse(tasks.isEmpty)
    XCTAssertLessThanOrEqual(tasks.count, CodexTaskProvider.defaultMaximumSessions)
    let running = tasks.filter { $0.work == .running }.count
    let completed = tasks.filter { $0.result == .completed }.count
    let desktopTargets = tasks.filter {
      $0.navigationTarget?.applicationBundleIdentifier == "com.openai.codex"
        && $0.navigationTarget?.deepLink?.hasPrefix("codex://threads/") == true
    }.count
    if ProcessInfo.processInfo.environment["OMAPET_EXPECT_CODEX_DESKTOP_TARGETS"] == "1" {
      XCTAssertGreaterThan(desktopTargets, 0)
    }
    print(
      "live_codex_tasks=\(tasks.count) running=\(running) completed=\(completed) desktop_targets=\(desktopTargets) initial=\(initialElapsed) refresh=\(refreshElapsed)"
    )
  }
}
