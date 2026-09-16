import Foundation
import XCTest

@testable import AgentPetCodex

final class CodexHookTrustManagerTests: XCTestCase {
  func testActivatePreservesUnrelatedStateAndTrustsOnlyExactOwnedHooks() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: hooksURL)
    let command = "'/tmp/omapet' hook codex"
    let fake = FakeCodexSession(
      hooksURL: hooksURL,
      command: command,
      hookCount: CodexHookConfiguration.eventNames.count,
      state: [
        "stale-owned": ["trusted_hash": "old"],
        "unrelated": ["trusted_hash": "keep"],
      ]
    )
    fake.effectiveState = [
      "managed-only": ["trusted_hash": "do-not-copy"],
      "stale-owned": ["trusted_hash": "old"],
      "unrelated": ["trusted_hash": "keep"],
    ]
    fake.extraHooks = [
      fake.hook(
        key: "project-spoof",
        hash: "sha256:spoof",
        source: "project",
        sourcePath: directory.appendingPathComponent("project-hooks.json").path
      )
    ]
    let manager = CodexHookTrustManager(
      hooksURL: hooksURL,
      expectedCommand: command,
      sessionFactory: { fake }
    )

    let change = try manager.activate(
      cwd: directory,
      expectedHookCount: CodexHookConfiguration.eventNames.count,
      replacing: ["stale-owned"]
    )

    XCTAssertTrue(change.changed)
    XCTAssertEqual(change.trustedHookCount, CodexHookConfiguration.eventNames.count)
    XCTAssertEqual(
      (fake.state["unrelated"] as? [String: String])?["trusted_hash"],
      "keep"
    )
    XCTAssertNil(fake.state["project-spoof"])
    XCTAssertNil(fake.state["stale-owned"])
    XCTAssertNil(fake.state["managed-only"])
    XCTAssertTrue(fake.expectedVersions.allSatisfy { !$0.isEmpty })
  }

  func testFailedVerificationRestoresOriginalHookState() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: hooksURL)
    let fake = FakeCodexSession(
      hooksURL: hooksURL,
      command: "command",
      hookCount: CodexHookConfiguration.eventNames.count,
      state: ["unrelated": ["trusted_hash": "keep"]]
    )
    fake.forceUntrusted = true
    let manager = CodexHookTrustManager(
      hooksURL: hooksURL,
      expectedCommand: "command",
      sessionFactory: { fake }
    )

    XCTAssertThrowsError(
      try manager.activate(
        cwd: directory,
        expectedHookCount: CodexHookConfiguration.eventNames.count
      )
    ) {
      XCTAssertEqual($0 as? CodexHookTrustManager.Error, .trustVerificationFailed)
    }
    XCTAssertEqual(Set(fake.state.keys), ["unrelated"])
  }

  func testRemoveTrustedKeysKeepsUnrelatedState() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: hooksURL)
    let fake = FakeCodexSession(
      hooksURL: hooksURL,
      command: "command",
      hookCount: 1,
      state: [
        "owned": ["trusted_hash": "remove"],
        "unrelated": ["trusted_hash": "keep"],
      ]
    )
    let manager = CodexHookTrustManager(
      hooksURL: hooksURL,
      expectedCommand: "command",
      sessionFactory: { fake }
    )

    XCTAssertTrue(try manager.removeTrustedHookKeys(["owned"]))
    XCTAssertNil(fake.state["owned"])
    XCTAssertNotNil(fake.state["unrelated"])
  }

  func testWarningsFailClosedInsteadOfTrustingPartialConfiguration() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: hooksURL)
    let fake = FakeCodexSession(
      hooksURL: hooksURL,
      command: "command",
      hookCount: CodexHookConfiguration.eventNames.count,
      state: [:]
    )
    fake.warnings = ["invalid user hook"]
    let manager = CodexHookTrustManager(
      hooksURL: hooksURL,
      expectedCommand: "command",
      sessionFactory: { fake }
    )

    XCTAssertThrowsError(try manager.inspect(cwd: directory)) {
      XCTAssertEqual($0 as? CodexHookTrustManager.Error, .hookConfigurationIssue)
    }
    XCTAssertTrue(fake.state.isEmpty)
  }

  func testRemovalFindsOwnedHooksAfterExecutablePathChanges() throws {
    let directory = temporaryDirectory()
    let hooksURL = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: hooksURL)
    let fake = FakeCodexSession(
      hooksURL: hooksURL,
      command: "old executable command",
      hookCount: 2,
      state: [:]
    )
    let manager = CodexHookTrustManager(
      hooksURL: hooksURL,
      expectedCommand: "new executable command",
      sessionFactory: { fake }
    )

    XCTAssertEqual(try manager.inspect(cwd: directory).hookCount, 0)
    XCTAssertEqual(try manager.keysForRemoval(cwd: directory), ["owned-0", "owned-1"])
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

private final class FakeCodexSession: CodexAppServerSessionProtocol, @unchecked Sendable {
  let hooksURL: URL
  let command: String
  let hookCount: Int
  var state: [String: Any]
  var effectiveState: [String: Any]?
  var extraHooks: [[String: Any]] = []
  var forceUntrusted = false
  var warnings: [String] = []
  var expectedVersions: [String] = []
  private var version = 1

  init(
    hooksURL: URL,
    command: String,
    hookCount: Int,
    state: [String: Any]
  ) {
    self.hooksURL = hooksURL.resolvingSymlinksInPath().standardizedFileURL
    self.command = command
    self.hookCount = hookCount
    self.state = state
  }

  func call(method: String, params: [String: Any]) throws -> [String: Any] {
    switch method {
    case "hooks/list":
      let owned = (0..<hookCount).map { index in
        hook(key: "owned-\(index)", hash: "sha256:\(index)")
      }
      return [
        "data": [
          [
            "cwd": "/tmp",
            "hooks": owned + extraHooks,
            "warnings": warnings,
            "errors": [[String: Any]](),
          ]
        ]
      ]
    case "config/read":
      return [
        "config": ["hooks": ["state": effectiveState ?? state]],
        "origins": [String: Any](),
        "layers": [
          [
            "name": [
              "type": "user",
              "file": hooksURL.deletingLastPathComponent()
                .appendingPathComponent("config.toml").path,
            ],
            "version": "version-\(version)",
            "config": ["hooks": ["state": state]],
          ]
        ],
      ]
    case "config/batchWrite":
      let expectedVersion = params["expectedVersion"] as? String ?? ""
      expectedVersions.append(expectedVersion)
      guard expectedVersion == "version-\(version)",
        let edits = params["edits"] as? [[String: Any]],
        let replacement = edits.first?["value"] as? [String: Any]
      else {
        throw CodexAppServerSession.Error.server(code: -1, message: "version mismatch")
      }
      state = replacement
      version += 1
      return ["status": "ok", "version": "version-\(version)", "filePath": "/tmp/config.toml"]
    default:
      throw CodexAppServerSession.Error.server(code: -1, message: "unexpected method")
    }
  }

  func close() {}

  func hook(
    key: String,
    hash: String,
    source: String = "user",
    sourcePath: String? = nil
  ) -> [String: Any] {
    let trustedHash = (state[key] as? [String: String])?["trusted_hash"]
    return [
      "key": key,
      "command": command,
      "currentHash": hash,
      "trustStatus": !forceUntrusted && trustedHash == hash ? "trusted" : "untrusted",
      "source": source,
      "sourcePath": sourcePath ?? hooksURL.path,
      "statusMessage": CodexHookConfiguration.ownershipMarker,
    ]
  }
}
