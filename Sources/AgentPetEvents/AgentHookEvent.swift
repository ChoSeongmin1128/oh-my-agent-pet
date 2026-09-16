import Foundation

public enum AgentHookProvider: String, Codable, CaseIterable, Sendable {
  case claude
  case codex
}

public struct StoredAgentHookEvent: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 2
  public static let supportedSchemaVersions: Set<Int> = [1, 2]

  public let schemaVersion: Int
  public let recordID: UUID
  public let receivedAtMilliseconds: Int64
  public let provider: AgentHookProvider
  public let hookEventName: String
  public let sessionID: String
  public let turnID: String?
  public let cwd: String
  public let source: String?
  public let notificationType: String?
  public let toolName: String?

  public init(
    recordID: UUID,
    receivedAtMilliseconds: Int64,
    provider: AgentHookProvider = .claude,
    hookEventName: String,
    sessionID: String,
    turnID: String? = nil,
    cwd: String,
    source: String?,
    notificationType: String?,
    toolName: String?
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.recordID = recordID
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.provider = provider
    self.hookEventName = hookEventName
    self.sessionID = sessionID
    self.turnID = turnID
    self.cwd = cwd
    self.source = source
    self.notificationType = notificationType
    self.toolName = toolName
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    recordID = try values.decode(UUID.self, forKey: .recordID)
    receivedAtMilliseconds = try values.decode(Int64.self, forKey: .receivedAtMilliseconds)
    switch schemaVersion {
    case 1:
      provider = .claude
    case Self.currentSchemaVersion:
      provider = try values.decode(AgentHookProvider.self, forKey: .provider)
    default:
      provider = try values.decodeIfPresent(AgentHookProvider.self, forKey: .provider) ?? .claude
    }
    hookEventName = try values.decode(String.self, forKey: .hookEventName)
    sessionID = try values.decode(String.self, forKey: .sessionID)
    turnID = try values.decodeIfPresent(String.self, forKey: .turnID)
    cwd = try values.decode(String.self, forKey: .cwd)
    source = try values.decodeIfPresent(String.self, forKey: .source)
    notificationType = try values.decodeIfPresent(String.self, forKey: .notificationType)
    toolName = try values.decodeIfPresent(String.self, forKey: .toolName)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case recordID = "record_id"
    case receivedAtMilliseconds = "received_at_ms"
    case provider
    case hookEventName = "hook_event_name"
    case sessionID = "session_id"
    case turnID = "turn_id"
    case cwd
    case source
    case notificationType = "notification_type"
    case toolName = "tool_name"
  }
}

struct AgentHookInput: Decodable {
  let hookEventName: String
  let sessionID: String
  let turnID: String?
  let cwd: String
  let source: String?
  let notificationType: String?
  let toolName: String?

  enum CodingKeys: String, CodingKey {
    case hookEventName = "hook_event_name"
    case sessionID = "session_id"
    case turnID = "turn_id"
    case cwd
    case source
    case notificationType = "notification_type"
    case toolName = "tool_name"
  }
}

enum AgentHookEventPolicy {
  private static let claudeEvents: Set<String> = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PermissionRequest", "Notification", "Elicitation",
    "Stop", "StopFailure", "SessionEnd",
  ]
  private static let codexEvents: Set<String> = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PermissionRequest", "Stop", "Interrupt", "SessionEnd",
  ]

  static func storedEvent(
    from input: AgentHookInput,
    provider: AgentHookProvider,
    now: Date,
    recordID: UUID
  ) -> StoredAgentHookEvent? {
    let supportedEvents = provider == .claude ? claudeEvents : codexEvents
    guard supportedEvents.contains(input.hookEventName),
      let sessionID = bounded(input.sessionID, maximum: 512),
      let cwd = bounded(input.cwd, maximum: 4_096)
    else {
      return nil
    }

    return StoredAgentHookEvent(
      recordID: recordID,
      receivedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
      provider: provider,
      hookEventName: input.hookEventName,
      sessionID: sessionID,
      turnID: bounded(input.turnID, maximum: 512),
      cwd: cwd,
      source: bounded(input.source, maximum: 128),
      notificationType: bounded(input.notificationType, maximum: 128),
      toolName: bounded(input.toolName, maximum: 256)
    )
  }

  private static func bounded(_ value: String?, maximum: Int) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= maximum else {
      return nil
    }
    return value
  }
}
