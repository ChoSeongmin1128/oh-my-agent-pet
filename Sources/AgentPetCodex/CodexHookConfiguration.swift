import Foundation

public enum CodexHookConfigurationError: Error, Equatable, Sendable {
  case invalidJSON
  case invalidRootObject
  case invalidHooksObject
  case invalidHookEvent(String)
}

public enum CodexHookInstallationState: String, Codable, Equatable, Sendable {
  case notConfigured = "not_configured"
  case connected
  case needsTrust = "needs_trust"
  case needsRepair = "needs_repair"
  case codexUnavailable = "codex_unavailable"
}

public struct CodexHookConfiguration: Sendable {
  public static let ownershipMarker = "Oh My Agent Pet session observer"
  public static let eventNames = [
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "PermissionRequest",
    "Stop",
    "Interrupt",
    "SessionEnd",
  ]

  public init() {}

  public func installing(in data: Data, executableURL: URL) throws -> Data {
    var root = try parse(data)
    try removeOwnedHandlers(from: &root)
    try addOwnedHandlers(to: &root, executableURL: executableURL)
    return try serialize(root)
  }

  public func removing(from data: Data) throws -> Data {
    var root = try parse(data)
    guard try ownedHandlerCount(in: root) > 0 else { return data }
    try removeOwnedHandlers(from: &root)
    return try serialize(root)
  }

  public func installationState(in data: Data, executableURL: URL) throws
    -> CodexHookInstallationState
  {
    let root = try parse(data)
    let handlers = try ownedHandlersByEvent(in: root)
    guard !handlers.isEmpty else { return .notConfigured }
    let expectedCommand = command(executableURL: executableURL)
    let complete =
      Set(handlers.keys) == Set(Self.eventNames)
      && handlers.values.allSatisfy { values in
        values.count == 1 && values[0] == expectedCommand
      }
    return complete ? .needsTrust : .needsRepair
  }

  public func ownedHandlerCount(in data: Data) throws -> Int {
    try ownedHandlerCount(in: parse(data))
  }

  public func command(executableURL: URL) -> String {
    let path = executableURL.resolvingSymlinksInPath().standardizedFileURL.path
    return "\(Self.shellQuote(path)) hook codex >/dev/null 2>/dev/null || :"
  }

  public func handler(executableURL: URL) -> [String: Any] {
    [
      "type": "command",
      "command": command(executableURL: executableURL),
      "timeout": 1,
      "statusMessage": Self.ownershipMarker,
    ]
  }

  private func addOwnedHandlers(to root: inout [String: Any], executableURL: URL) throws {
    var hooks: [String: Any]
    if let value = root["hooks"] {
      guard let existing = value as? [String: Any] else {
        throw CodexHookConfigurationError.invalidHooksObject
      }
      hooks = existing
    } else {
      hooks = [:]
    }

    let ownedHandler = handler(executableURL: executableURL)
    for eventName in Self.eventNames {
      var groups = try hookGroups(named: eventName, in: hooks)
      groups.append(["hooks": [ownedHandler]])
      hooks[eventName] = groups
    }
    root["hooks"] = hooks
  }

  private func removeOwnedHandlers(from root: inout [String: Any]) throws {
    guard let rawHooks = root["hooks"] else { return }
    guard var hooks = rawHooks as? [String: Any] else {
      throw CodexHookConfigurationError.invalidHooksObject
    }

    for eventName in Array(hooks.keys) {
      let groups = try hookGroups(named: eventName, in: hooks)
      var retainedGroups: [[String: Any]] = []
      for var group in groups {
        guard let handlers = group["hooks"] as? [[String: Any]] else {
          throw CodexHookConfigurationError.invalidHookEvent(eventName)
        }
        let retainedHandlers = handlers.filter { !isOwned($0) }
        if !retainedHandlers.isEmpty {
          group["hooks"] = retainedHandlers
          retainedGroups.append(group)
        }
      }
      if retainedGroups.isEmpty {
        hooks.removeValue(forKey: eventName)
      } else {
        hooks[eventName] = retainedGroups
      }
    }

    if hooks.isEmpty {
      root.removeValue(forKey: "hooks")
    } else {
      root["hooks"] = hooks
    }
  }

  private func ownedHandlersByEvent(in root: [String: Any]) throws -> [String: [String]] {
    guard let rawHooks = root["hooks"] else { return [:] }
    guard let hooks = rawHooks as? [String: Any] else {
      throw CodexHookConfigurationError.invalidHooksObject
    }
    var result: [String: [String]] = [:]
    for eventName in hooks.keys {
      for group in try hookGroups(named: eventName, in: hooks) {
        guard let handlers = group["hooks"] as? [[String: Any]] else {
          throw CodexHookConfigurationError.invalidHookEvent(eventName)
        }
        for handler in handlers where isOwned(handler) {
          guard let command = handler["command"] as? String else {
            throw CodexHookConfigurationError.invalidHookEvent(eventName)
          }
          result[eventName, default: []].append(command)
        }
      }
    }
    return result
  }

  private func ownedHandlerCount(in root: [String: Any]) throws -> Int {
    try ownedHandlersByEvent(in: root).values.reduce(0) { $0 + $1.count }
  }

  private func hookGroups(named eventName: String, in hooks: [String: Any]) throws
    -> [[String: Any]]
  {
    guard let value = hooks[eventName] else { return [] }
    guard let groups = value as? [[String: Any]] else {
      throw CodexHookConfigurationError.invalidHookEvent(eventName)
    }
    return groups
  }

  private func isOwned(_ handler: [String: Any]) -> Bool {
    handler["statusMessage"] as? String == Self.ownershipMarker
  }

  private func parse(_ data: Data) throws -> [String: Any] {
    let source = data.isEmpty ? Data("{}".utf8) : data
    let value: Any
    do {
      value = try JSONSerialization.jsonObject(with: source)
    } catch {
      throw CodexHookConfigurationError.invalidJSON
    }
    guard let root = value as? [String: Any] else {
      throw CodexHookConfigurationError.invalidRootObject
    }
    return root
  }

  private func serialize(_ root: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: root,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) + Data([0x0A])
  }

  private static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
  }
}
