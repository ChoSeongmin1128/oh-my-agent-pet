import AgentPetCore
import Darwin
import Foundation

struct CodexHookTrustInspection: Equatable, Sendable {
  let hookCount: Int
  let trustedHookCount: Int
  let keys: Set<String>
}

struct CodexHookTrustChange: Equatable, Sendable {
  let trustedHookCount: Int
  let changed: Bool
}

protocol CodexHookTrustManaging: Sendable {
  func inspect(cwd: URL) throws -> CodexHookTrustInspection
  func keysForRemoval(cwd: URL) throws -> Set<String>
  func activate(
    cwd: URL,
    expectedHookCount: Int,
    replacing keys: Set<String>
  ) throws -> CodexHookTrustChange
  func removeTrustedHookKeys(_ keys: Set<String>) throws -> Bool
}

struct CodexHookTrustManager: CodexHookTrustManaging {
  enum Error: Swift.Error, Equatable {
    case codexExecutableUnavailable
    case malformedResponse(String)
    case hookConfigurationIssue
    case hooksMissing(expected: Int, found: Int)
    case trustVerificationFailed
    case rollbackFailed
  }

  private let hooksURL: URL
  private let expectedCommand: String
  private let sessionFactory: @Sendable () throws -> any CodexAppServerSessionProtocol

  init(
    hooksURL: URL,
    expectedCommand: String,
    codexExecutableURL: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.hooksURL = hooksURL.resolvingSymlinksInPath().standardizedFileURL
    self.expectedCommand = expectedCommand
    sessionFactory = {
      let executableURL =
        try codexExecutableURL
        ?? Self.resolveCodexExecutable(environment: environment)
      return try CodexAppServerSession(executableURL: executableURL, environment: environment)
    }
  }

  init(
    hooksURL: URL,
    expectedCommand: String,
    sessionFactory: @escaping @Sendable () throws -> any CodexAppServerSessionProtocol
  ) {
    self.hooksURL = hooksURL.resolvingSymlinksInPath().standardizedFileURL
    self.expectedCommand = expectedCommand
    self.sessionFactory = sessionFactory
  }

  func inspect(cwd: URL) throws -> CodexHookTrustInspection {
    let session = try sessionFactory()
    defer { session.close() }
    let hooks = try listOwnedHooks(session: session, cwd: cwd, requireExpectedCommand: true)
    return CodexHookTrustInspection(
      hookCount: hooks.count,
      trustedHookCount: hooks.count { $0.trustStatus == "trusted" },
      keys: Set(hooks.map(\.key))
    )
  }

  func keysForRemoval(cwd: URL) throws -> Set<String> {
    let session = try sessionFactory()
    defer { session.close() }
    return Set(
      try listOwnedHooks(session: session, cwd: cwd, requireExpectedCommand: false).map(\.key)
    )
  }

  func activate(
    cwd: URL,
    expectedHookCount: Int,
    replacing keys: Set<String> = []
  ) throws -> CodexHookTrustChange {
    let session = try sessionFactory()
    defer { session.close() }
    let hooks = try listOwnedHooks(session: session, cwd: cwd, requireExpectedCommand: true)
    guard hooks.count == expectedHookCount else {
      throw Error.hooksMissing(expected: expectedHookCount, found: hooks.count)
    }

    let original = try readHookState(session: session)
    var updated = original.state
    for key in keys { updated.removeValue(forKey: key) }
    for hook in hooks {
      updated[hook.key] = ["trusted_hash": hook.currentHash]
    }
    let changed = !NSDictionary(dictionary: original.state).isEqual(to: updated)

    do {
      if changed {
        try replaceHookState(updated, expectedVersion: original.version, session: session)
      }
      let verified = try listOwnedHooks(
        session: session,
        cwd: cwd,
        requireExpectedCommand: true
      )
      guard verified.count == expectedHookCount,
        verified.allSatisfy({ $0.trustStatus == "trusted" })
      else {
        throw Error.trustVerificationFailed
      }
    } catch {
      let activationError = error
      if changed {
        do {
          try restoreHookState(original.state, session: session)
        } catch {
          throw Error.rollbackFailed
        }
      }
      throw activationError
    }

    return CodexHookTrustChange(trustedHookCount: hooks.count, changed: changed)
  }

  func removeTrustedHookKeys(_ keys: Set<String>) throws -> Bool {
    guard !keys.isEmpty else { return false }
    let session = try sessionFactory()
    defer { session.close() }
    let original = try readHookState(session: session)
    var updated = original.state
    for key in keys { updated.removeValue(forKey: key) }
    let changed = !NSDictionary(dictionary: original.state).isEqual(to: updated)
    guard changed else { return false }

    do {
      try replaceHookState(updated, expectedVersion: original.version, session: session)
      let verified = try readHookState(session: session)
      guard keys.allSatisfy({ verified.state[$0] == nil }) else {
        throw Error.trustVerificationFailed
      }
    } catch {
      let removalError = error
      do {
        try restoreHookState(original.state, session: session)
      } catch {
        throw Error.rollbackFailed
      }
      throw removalError
    }
    return true
  }

  private func listOwnedHooks(
    session: any CodexAppServerSessionProtocol,
    cwd: URL,
    requireExpectedCommand: Bool
  ) throws -> [CodexHookRecord] {
    let result = try session.call(method: "hooks/list", params: ["cwds": [cwd.path]])
    guard let data = result["data"] as? [[String: Any]] else {
      throw Error.malformedResponse("hooks/list")
    }
    let expectedPath = hooksURL.path
    var records: [CodexHookRecord] = []
    for item in data {
      guard let hooks = item["hooks"] as? [[String: Any]],
        let warnings = item["warnings"] as? [String],
        let errors = item["errors"] as? [[String: Any]]
      else {
        throw Error.malformedResponse("hooks/list")
      }
      guard warnings.isEmpty, errors.isEmpty else {
        throw Error.hookConfigurationIssue
      }
      for hook in hooks {
        guard let key = hook["key"] as? String,
          let currentHash = hook["currentHash"] as? String,
          let trustStatus = hook["trustStatus"] as? String,
          let source = hook["source"] as? String,
          let sourcePath = hook["sourcePath"] as? String
        else {
          throw Error.malformedResponse("hooks/list")
        }
        let canonicalSourcePath = URL(fileURLWithPath: sourcePath)
          .resolvingSymlinksInPath().standardizedFileURL.path
        if source == "user",
          canonicalSourcePath == expectedPath,
          hook["statusMessage"] as? String == CodexHookConfiguration.ownershipMarker,
          !requireExpectedCommand || hook["command"] as? String == expectedCommand
        {
          records.append(
            CodexHookRecord(key: key, currentHash: currentHash, trustStatus: trustStatus)
          )
        }
      }
    }
    return records
  }

  private func readHookState(
    session: any CodexAppServerSessionProtocol
  ) throws -> CodexHookStateSnapshot {
    let result = try session.call(
      method: "config/read",
      params: ["includeLayers": true]
    )
    guard result["config"] is [String: Any],
      let layers = result["layers"] as? [[String: Any]]
    else {
      throw Error.malformedResponse("config/read")
    }
    let expectedConfigPath = hooksURL.deletingLastPathComponent()
      .appendingPathComponent("config.toml")
      .resolvingSymlinksInPath().standardizedFileURL.path
    let userLayer = layers.first { layer in
      guard let name = layer["name"] as? [String: Any],
        name["type"] as? String == "user",
        let file = name["file"] as? String
      else { return false }
      return URL(fileURLWithPath: file).resolvingSymlinksInPath().standardizedFileURL.path
        == expectedConfigPath
        && (name["profile"] == nil || name["profile"] is NSNull)
    }
    guard let userLayer,
      let userConfig = userLayer["config"] as? [String: Any],
      let version = userLayer["version"] as? String
    else {
      throw Error.malformedResponse("config/read")
    }
    let hooks = userConfig["hooks"] as? [String: Any]
    let state: [String: Any]
    if let rawState = hooks?["state"] {
      guard let object = rawState as? [String: Any] else {
        throw Error.malformedResponse("config/read")
      }
      state = object
    } else {
      state = [:]
    }
    return CodexHookStateSnapshot(state: state, version: version)
  }

  private func replaceHookState(
    _ state: [String: Any],
    expectedVersion: String,
    session: any CodexAppServerSessionProtocol
  ) throws {
    _ = try session.call(
      method: "config/batchWrite",
      params: [
        "edits": [
          [
            "keyPath": "hooks.state",
            "value": state,
            "mergeStrategy": "replace",
          ]
        ],
        "expectedVersion": expectedVersion,
        "reloadUserConfig": true,
      ]
    )
  }

  private func restoreHookState(
    _ state: [String: Any],
    session: any CodexAppServerSessionProtocol
  ) throws {
    let current = try readHookState(session: session)
    try replaceHookState(state, expectedVersion: current.version, session: session)
  }

  static func resolveCodexExecutable(environment: [String: String]) throws -> URL {
    var candidates: [String] = []
    if let configuredPath = environment["CODEX_CLI_PATH"], !configuredPath.isEmpty {
      candidates.append(configuredPath)
    }
    candidates += [
      "/Applications/ChatGPT.app/Contents/Resources/codex",
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
    ]
    candidates += (environment["PATH"] ?? "")
      .split(separator: ":")
      .map { "\($0)/codex" }

    if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
      return URL(fileURLWithPath: path)
    }
    throw Error.codexExecutableUnavailable
  }
}

private struct CodexHookRecord {
  let key: String
  let currentHash: String
  let trustStatus: String
}

private struct CodexHookStateSnapshot {
  let state: [String: Any]
  let version: String
}
