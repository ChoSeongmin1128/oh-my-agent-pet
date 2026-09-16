import AgentPetCore
import Foundation
import XCTest

@testable import AgentPetNavigation

final class TaskNavigationPlannerTests: XCTestCase {
  func testCodexAndClaudeDeepLinksRequireExactValidatedIdentifiers() throws {
    let codex = TaskNavigationTarget(
      surface: .desktop,
      applicationBundleIdentifier: "com.openai.codex",
      deepLink: "codex://threads/11111111-1111-1111-1111-111111111111"
    )
    let claude = TaskNavigationTarget(
      surface: .desktop,
      applicationBundleIdentifier: "com.anthropic.claudefordesktop",
      deepLink: "claude://code/continue?session=local_22222222-2222-2222-2222-222222222222"
    )

    guard case .openDeepLink(let codexURL, _) = TaskNavigationPlanner.plan(for: codex),
      case .openDeepLink(let claudeURL, _) = TaskNavigationPlanner.plan(for: claude)
    else {
      return XCTFail("Expected validated deep links")
    }
    XCTAssertEqual(codexURL.absoluteString, codex.deepLink)
    XCTAssertEqual(claudeURL.absoluteString, claude.deepLink)

    let malformed = TaskNavigationTarget(
      surface: .desktop,
      applicationBundleIdentifier: "com.openai.codex",
      deepLink: "codex://threads/../../settings"
    )
    XCTAssertEqual(
      TaskNavigationPlanner.plan(for: malformed),
      .activateApplication(bundleIdentifier: "com.openai.codex")
    )
    let unexpectedUserInfo = TaskNavigationTarget(
      surface: .desktop,
      applicationBundleIdentifier: "com.openai.codex",
      deepLink: "codex://other@threads/11111111-1111-1111-1111-111111111111"
    )
    XCTAssertEqual(
      TaskNavigationPlanner.plan(for: unexpectedUserInfo),
      .activateApplication(bundleIdentifier: "com.openai.codex")
    )
  }

  func testITermSessionUsesOfficialRevealURL() throws {
    let target = TaskNavigationTarget(
      surface: .terminal,
      applicationBundleIdentifier: "com.googlecode.iterm2",
      terminalSessionID: "w0t1p0:11111111-1111-1111-1111-111111111111",
      tty: "/dev/ttys001"
    )

    guard case .openDeepLink(let url, let fallback) = TaskNavigationPlanner.plan(for: target)
    else { return XCTFail("Expected iTerm reveal URL") }

    XCTAssertEqual(fallback, "com.googlecode.iterm2")
    XCTAssertEqual(url.scheme, "iterm2")
    XCTAssertEqual(url.path, "reveal")
    XCTAssertEqual(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
      target.terminalSessionID
    )
  }

  func testTerminalTTYBuildsSelectionScriptAndRejectsUnsafeTTY() {
    let target = TaskNavigationTarget(
      surface: .terminal,
      applicationBundleIdentifier: "com.apple.Terminal",
      tty: "/dev/ttys009"
    )
    guard case .runAppleScript(let script, _) = TaskNavigationPlanner.plan(for: target)
    else { return XCTFail("Expected Terminal selection script") }
    XCTAssertTrue(script.contains("/dev/ttys009"))
    XCTAssertTrue(script.contains("selected tab of targetWindow"))

    let unsafe = TaskNavigationTarget(
      surface: .terminal,
      applicationBundleIdentifier: "com.apple.Terminal",
      tty: #"/dev/ttys001" & do shell script "bad" & ""#
    )
    XCTAssertEqual(
      TaskNavigationPlanner.plan(for: unsafe),
      .activateApplication(bundleIdentifier: "com.apple.Terminal")
    )
  }

  @MainActor
  func testNavigatorDistinguishesExactAppOnlyAndFailure() {
    let backend = FakeNavigationBackend()
    let navigator = TaskNavigator(backend: backend)
    let target = TaskNavigationTarget(
      surface: .desktop,
      applicationBundleIdentifier: "com.openai.codex",
      deepLink: "codex://threads/11111111-1111-1111-1111-111111111111"
    )
    let task = snapshot(target: target)

    backend.openResult = true
    XCTAssertEqual(navigator.navigate(to: task), .exact)

    backend.openResult = false
    backend.activateResult = true
    XCTAssertEqual(navigator.navigate(to: task), .appOnly)

    backend.activateResult = false
    XCTAssertEqual(navigator.navigate(to: task), .failed)
  }

  private func snapshot(target: TaskNavigationTarget) -> AgentTaskSnapshot {
    AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: ProviderIdentifier("codex")!,
        profileID: "default",
        dataRoot: "/tmp",
        taskID: "task",
        executionID: "execution",
        turnID: "turn"
      ),
      title: "Task",
      work: .running,
      result: .none,
      waiting: .none,
      lastPromptAt: nil,
      interventionRequestedAt: nil,
      completedAt: nil,
      updatedAt: .distantPast,
      hasUnseenCompletion: false,
      navigationTarget: target
    )
  }
}

@MainActor
private final class FakeNavigationBackend: TaskNavigationBackend {
  var openResult = false
  var activateResult = false

  func open(_ url: URL) -> Bool { openResult }
  func runAppleScript(_ source: String) -> Bool { false }
  func activateApplication(bundleIdentifier: String) -> Bool { activateResult }
}
