import Foundation
import XCTest

@testable import AgentPetClaude

final class ClaudeDesktopIndexLiveTests: XCTestCase {
  func testConfiguredDesktopIndexWhenRequested() throws {
    guard let home = ProcessInfo.processInfo.environment["OMAPET_LIVE_CLAUDE_HOME"] else {
      throw XCTSkip("Set OMAPET_LIVE_CLAUDE_HOME for the read-only desktop index check.")
    }
    let paths = ClaudePaths(
      homeDirectory: URL(fileURLWithPath: home, isDirectory: true),
      environment: [:]
    )
    var index = ClaudeDesktopSessionIndex(
      sessionsDirectory: paths.desktopSessionsDirectory
    )
    let startedAt = ContinuousClock.now

    let routes = index.routes()
    let initialElapsed = startedAt.duration(to: .now)
    let refreshStartedAt = ContinuousClock.now
    let refreshed = index.routes()
    let refreshElapsed = refreshStartedAt.duration(to: .now)

    XCTAssertFalse(routes.isEmpty)
    XCTAssertEqual(routes, refreshed)
    XCTAssertTrue(routes.values.allSatisfy { $0.hasPrefix("local_") })
    print(
      "live_claude_desktop_routes=\(routes.count) initial=\(initialElapsed) refresh=\(refreshElapsed)"
    )
  }
}
