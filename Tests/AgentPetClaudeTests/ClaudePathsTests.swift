import AgentPetClaude
import XCTest

final class ClaudePathsTests: XCTestCase {
  func testDefaultsUseHomeForClaudeAndApplicationSupport() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let paths = ClaudePaths(homeDirectory: home, environment: [:])

    XCTAssertEqual(paths.settingsURL.path, "/Users/example/.claude/settings.json")
    XCTAssertEqual(
      paths.eventsURL.path,
      "/Users/example/Library/Application Support/Oh My Agent Pet/events.ndjson"
    )
    XCTAssertEqual(
      paths.desktopSessionsDirectory.path,
      "/Users/example/Library/Application Support/Claude/claude-code-sessions"
    )
  }

  func testClaudeConfigDirectoryExpandsHomePrefix() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let paths = ClaudePaths(
      homeDirectory: home,
      environment: ["CLAUDE_CONFIG_DIR": "~/Claude Config"]
    )

    XCTAssertEqual(paths.settingsURL.path, "/Users/example/Claude Config/settings.json")
  }
}
