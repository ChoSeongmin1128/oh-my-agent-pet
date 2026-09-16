import AgentPetCodex
import XCTest

final class CodexPathsTests: XCTestCase {
  func testDefaultsToCodexDirectoryUnderHome() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let paths = CodexPaths(homeDirectory: home, environment: [:])

    XCTAssertEqual(paths.dataRoot.path, "/Users/example/.codex")
    XCTAssertEqual(paths.sessionsDirectory.path, "/Users/example/.codex/sessions")
    XCTAssertEqual(paths.sessionIndexURL.path, "/Users/example/.codex/session_index.jsonl")
  }

  func testCodexHomeExpandsHomePrefix() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let paths = CodexPaths(
      homeDirectory: home,
      environment: ["CODEX_HOME": "~/Codex Data"]
    )

    XCTAssertEqual(paths.dataRoot.path, "/Users/example/Codex Data")
  }
}
