import Foundation

public struct StoredClaudeHookEvent: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let recordID: UUID
  public let receivedAtMilliseconds: Int64
  public let hookEventName: String
  public let sessionID: String
  public let cwd: String
  public let source: String?
  public let notificationType: String?
  public let toolName: String?

  public init(
    recordID: UUID,
    receivedAtMilliseconds: Int64,
    hookEventName: String,
    sessionID: String,
    cwd: String,
    source: String?,
    notificationType: String?,
    toolName: String?
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.recordID = recordID
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.hookEventName = hookEventName
    self.sessionID = sessionID
    self.cwd = cwd
    self.source = source
    self.notificationType = notificationType
    self.toolName = toolName
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case recordID = "record_id"
    case receivedAtMilliseconds = "received_at_ms"
    case hookEventName = "hook_event_name"
    case sessionID = "session_id"
    case cwd
    case source
    case notificationType = "notification_type"
    case toolName = "tool_name"
  }
}

struct ClaudeHookInput: Decodable {
  let hookEventName: String
  let sessionID: String
  let cwd: String
  let source: String?
  let notificationType: String?
  let toolName: String?

  enum CodingKeys: String, CodingKey {
    case hookEventName = "hook_event_name"
    case sessionID = "session_id"
    case cwd
    case source
    case notificationType = "notification_type"
    case toolName = "tool_name"
  }
}

enum ClaudeHookEventPolicy {
  static let supportedEvents: Set<String> = [
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

  static func storedEvent(
    from input: ClaudeHookInput,
    now: Date,
    recordID: UUID
  ) -> StoredClaudeHookEvent? {
    guard supportedEvents.contains(input.hookEventName),
      let sessionID = bounded(input.sessionID, maximum: 512),
      let cwd = bounded(input.cwd, maximum: 4_096)
    else {
      return nil
    }

    return StoredClaudeHookEvent(
      recordID: recordID,
      receivedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
      hookEventName: input.hookEventName,
      sessionID: sessionID,
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
