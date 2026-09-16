import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexAppServerIntegrationTests: XCTestCase {
  func testTemporaryCodexHomeConnectsTrustsAndRemovesOwnedHooks() throws {
    var environment = ProcessInfo.processInfo.environment
    let codex: URL
    do {
      codex = try CodexHookTrustManager.resolveCodexExecutable(environment: environment)
    } catch {
      throw XCTSkip("Codex CLI is not installed on this test host.")
    }
    let home = temporaryDirectory()
    let codexHome = home.appendingPathComponent("codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try Data("[hooks.state.unrelated]\ntrusted_hash = \"keep\"\n".utf8).write(
      to: codexHome.appendingPathComponent("config.toml")
    )
    environment["CODEX_HOME"] = codexHome.path
    environment["CODEX_CLI_PATH"] = codex.path
    let service = CodexSetupService(
      homeDirectory: home,
      environment: environment,
      executableURL: URL(fileURLWithPath: "/bin/cat")
    )

    let connected = try service.connect(dryRun: false)
    let status = try service.status()
    let disconnected = try service.disconnect(dryRun: false)
    let config = try String(
      contentsOf: codexHome.appendingPathComponent("config.toml"),
      encoding: .utf8
    )

    XCTAssertEqual(connected.trustedHookCount, CodexHookConfiguration.eventNames.count)
    XCTAssertEqual(status.status, .connected)
    XCTAssertEqual(disconnected.status, .notConfigured)
    XCTAssertFalse(FileManager.default.fileExists(atPath: service.hooksURL.path))
    XCTAssertTrue(config.contains("keep"))
    XCTAssertFalse(config.contains("hooks.json:"))
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
