import Foundation

public enum AgentHookProvider: String, Codable, CaseIterable, Sendable {
  case claude
  case codex
}

public enum AgentHookClientSurface: String, Codable, Sendable {
  case desktop
  case terminal
}

public struct StoredAgentHookEvent: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 3
  public static let supportedSchemaVersions: Set<Int> = [1, 2, 3]

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
  public let clientSurface: AgentHookClientSurface?
  public let applicationBundleIdentifier: String?
  public let terminalSessionID: String?
  public let tty: String?

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
    toolName: String?,
    clientSurface: AgentHookClientSurface? = nil,
    applicationBundleIdentifier: String? = nil,
    terminalSessionID: String? = nil,
    tty: String? = nil
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
    self.clientSurface = clientSurface
    self.applicationBundleIdentifier = applicationBundleIdentifier
    self.terminalSessionID = terminalSessionID
    self.tty = tty
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    recordID = try values.decode(UUID.self, forKey: .recordID)
    receivedAtMilliseconds = try values.decode(Int64.self, forKey: .receivedAtMilliseconds)
    switch schemaVersion {
    case 1:
      provider = .claude
    case 2, Self.currentSchemaVersion:
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
    clientSurface = try values.decodeIfPresent(
      AgentHookClientSurface.self,
      forKey: .clientSurface
    )
    applicationBundleIdentifier = try values.decodeIfPresent(
      String.self,
      forKey: .applicationBundleIdentifier
    )
    terminalSessionID = try values.decodeIfPresent(String.self, forKey: .terminalSessionID)
    tty = try values.decodeIfPresent(String.self, forKey: .tty)
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
    case clientSurface = "client_surface"
    case applicationBundleIdentifier = "application_bundle_id"
    case terminalSessionID = "terminal_session_id"
    case tty
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
    environment: [String: String],
    tty: String?,
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

    let location = executionLocation(
      provider: provider,
      environment: environment,
      tty: tty
    )
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
      toolName: bounded(input.toolName, maximum: 256),
      clientSurface: location?.surface,
      applicationBundleIdentifier: location?.bundleIdentifier,
      terminalSessionID: location?.terminalSessionID,
      tty: location?.tty
    )
  }

  private static func executionLocation(
    provider: AgentHookProvider,
    environment: [String: String],
    tty: String?
  ) -> HookExecutionLocation? {
    if provider == .claude,
      environment["CLAUDE_CODE_ENTRYPOINT"]?.lowercased().contains("desktop") == true
    {
      return HookExecutionLocation(
        surface: .desktop,
        bundleIdentifier: "com.anthropic.claudefordesktop",
        terminalSessionID: nil,
        tty: nil
      )
    }
    if provider == .codex,
      environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == "Codex"
    {
      return HookExecutionLocation(
        surface: .desktop,
        bundleIdentifier: "com.openai.codex",
        terminalSessionID: nil,
        tty: nil
      )
    }

    let terminalProgram = environment["TERM_PROGRAM"]?.lowercased()
    let bundleIdentifier: String?
    switch terminalProgram {
    case "iterm.app", "iterm2":
      bundleIdentifier = "com.googlecode.iterm2"
    case "apple_terminal", "terminal", "terminal.app":
      bundleIdentifier = "com.apple.Terminal"
    default:
      bundleIdentifier = nil
    }
    let safeTTY = validatedTTY(tty)
    let safeSessionID =
      bundleIdentifier == "com.googlecode.iterm2"
      ? validatedTerminalSessionID(environment["ITERM_SESSION_ID"])
      : nil
    guard let bundleIdentifier, safeSessionID != nil || safeTTY != nil else { return nil }
    return HookExecutionLocation(
      surface: .terminal,
      bundleIdentifier: bundleIdentifier,
      terminalSessionID: safeSessionID,
      tty: safeTTY
    )
  }

  private static func validatedTerminalSessionID(_ value: String?) -> String? {
    guard let value = bounded(value, maximum: 256),
      let separator = value.lastIndex(of: ":"),
      UUID(uuidString: String(value[value.index(after: separator)...])) != nil,
      value.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics
          .union(CharacterSet(charactersIn: "-_:.")).contains($0)
      })
    else { return nil }
    return value
  }

  private static func validatedTTY(_ value: String?) -> String? {
    guard let value = bounded(value, maximum: 128), value.hasPrefix("/dev/tty") else {
      return nil
    }
    let suffix = value.dropFirst(8)
    guard !suffix.isEmpty,
      suffix.allSatisfy({ $0.isLetter || $0.isNumber })
    else { return nil }
    return value
  }

  private static func bounded(_ value: String?, maximum: Int) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= maximum else {
      return nil
    }
    return value
  }
}

private struct HookExecutionLocation {
  let surface: AgentHookClientSurface
  let bundleIdentifier: String
  let terminalSessionID: String?
  let tty: String?
}
