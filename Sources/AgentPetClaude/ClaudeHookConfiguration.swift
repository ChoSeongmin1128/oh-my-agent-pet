import AgentPetCore
import Foundation

public enum ClaudeHookConfigurationError: Error, Equatable, Sendable {
  case invalidJSON
  case invalidRootObject
  case invalidHooksObject
  case invalidHookEvent(String)
}

public enum ClaudeHookInstallationState: String, Codable, Equatable, Sendable {
  case notConfigured
  case connected
  case connectedButDisabled
  case needsRepair
}

public struct ClaudeHookConfiguration: Sendable {
  public static let ownershipMarker = AgentPetProduct.hookOwnershipMarker
  public static let shellMarker = "oh-my-agent-pet-hook-v1"
  public static let eventNames = [
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "PermissionRequest",
    "Notification",
    "Elicitation",
    "Stop",
    "StopFailure",
    "SessionEnd",
  ]

  private static let shellScript = """
    if [ "$#" -ge 1 ] && [ -x "$1" ]; then
      "$1" hook claude >/dev/null 2>/dev/null || :
    fi
    exit 0
    """

  public init() {}

  public func installing(in data: Data, executableURL: URL) throws -> Data {
    var root = try parse(data)
    try removeOwnedHandlers(from: &root)
    try addOwnedHandlers(to: &root, executableURL: executableURL)
    return try serialize(root)
  }

  public func removing(from data: Data) throws -> Data {
    var root = try parse(data)
    guard try !ownedExecutablePaths(in: root).isEmpty else {
      return data
    }
    try removeOwnedHandlers(from: &root)
    return try serialize(root)
  }

  public func installationState(in data: Data, executableURL: URL) throws
    -> ClaudeHookInstallationState
  {
    let root = try parse(data)
    let pathsByEvent = try ownedExecutablePathsByEvent(in: root)
    let paths = pathsByEvent.values.flatMap { $0 }
    guard !paths.isEmpty else {
      return .notConfigured
    }

    let expectedPath = executableURL.standardizedFileURL.path
    let expectedEvents = Set(Self.eventNames)
    let isComplete =
      Set(pathsByEvent.keys) == expectedEvents
      && pathsByEvent.values.allSatisfy { $0 == [expectedPath] }
    guard isComplete else {
      return .needsRepair
    }
    if root["disableAllHooks"] as? Bool == true {
      return .connectedButDisabled
    }
    return .connected
  }

  public func ownedHandlerCount(in data: Data) throws -> Int {
    try ownedExecutablePaths(in: parse(data)).count
  }

  public func handler(executableURL: URL) -> [String: Any] {
    [
      "type": "command",
      "command": "/bin/sh",
      "args": [
        "-c",
        Self.shellScript,
        Self.shellMarker,
        executableURL.standardizedFileURL.path,
      ],
      "timeout": 1,
      "statusMessage": Self.ownershipMarker,
    ]
  }

  private func addOwnedHandlers(to root: inout [String: Any], executableURL: URL) throws {
    var hooks: [String: Any]
    if let value = root["hooks"] {
      guard let existing = value as? [String: Any] else {
        throw ClaudeHookConfigurationError.invalidHooksObject
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
    guard let rawHooks = root["hooks"] else {
      return
    }
    guard var hooks = rawHooks as? [String: Any] else {
      throw ClaudeHookConfigurationError.invalidHooksObject
    }

    for eventName in Array(hooks.keys) {
      let groups = try hookGroups(named: eventName, in: hooks)
      var retainedGroups: [[String: Any]] = []
      for var group in groups {
        guard let rawHandlers = group["hooks"],
          let handlers = rawHandlers as? [[String: Any]]
        else {
          throw ClaudeHookConfigurationError.invalidHookEvent(eventName)
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

  private func ownedExecutablePaths(in root: [String: Any]) throws -> [String] {
    try ownedExecutablePathsByEvent(in: root).values.flatMap { $0 }
  }

  private func ownedExecutablePathsByEvent(in root: [String: Any]) throws -> [String: [String]] {
    guard let rawHooks = root["hooks"] else {
      return [:]
    }
    guard let hooks = rawHooks as? [String: Any] else {
      throw ClaudeHookConfigurationError.invalidHooksObject
    }

    var paths: [String: [String]] = [:]
    for eventName in hooks.keys {
      for group in try hookGroups(named: eventName, in: hooks) {
        guard let handlers = group["hooks"] as? [[String: Any]] else {
          throw ClaudeHookConfigurationError.invalidHookEvent(eventName)
        }
        for handler in handlers where isOwned(handler) {
          guard let args = handler["args"] as? [String], args.count >= 4 else {
            continue
          }
          paths[eventName, default: []].append(
            URL(fileURLWithPath: args[3]).standardizedFileURL.path
          )
        }
      }
    }
    return paths
  }

  private func hookGroups(named eventName: String, in hooks: [String: Any]) throws
    -> [[String: Any]]
  {
    guard let value = hooks[eventName] else {
      return []
    }
    guard let groups = value as? [[String: Any]] else {
      throw ClaudeHookConfigurationError.invalidHookEvent(eventName)
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
      throw ClaudeHookConfigurationError.invalidJSON
    }
    guard let root = value as? [String: Any] else {
      throw ClaudeHookConfigurationError.invalidRootObject
    }
    return root
  }

  private func serialize(_ root: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: root,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) + Data([0x0A])
  }
}
