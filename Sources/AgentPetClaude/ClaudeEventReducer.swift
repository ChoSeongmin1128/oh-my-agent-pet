import AgentPetCore
import Foundation

public struct ClaudeEventReducer: Sendable {
  private static let maximumRecentRecordIDs = 4_096
  private static let recordIDTrimCount = 1_024

  private let provider: ProviderIdentifier
  private let profileID: String
  private let dataRoot: String
  private var sessions: [String: SessionState] = [:]
  private var appliedRecords: Set<UUID> = []
  private var appliedRecordOrder: [UUID] = []

  public init(profileID: String = "default", dataRoot: String) {
    provider = .claude
    self.profileID = profileID
    self.dataRoot = dataRoot
  }

  public var snapshots: [AgentTaskSnapshot] {
    sessions.values.map(snapshot).sorted { $0.identity.stableKey < $1.identity.stableKey }
  }

  public mutating func apply(_ event: StoredClaudeHookEvent) {
    guard event.provider == .claude else { return }
    guard appliedRecords.insert(event.recordID).inserted else {
      return
    }
    appliedRecordOrder.append(event.recordID)
    trimAppliedRecordsIfNeeded()

    let timestamp = Date(timeIntervalSince1970: Double(event.receivedAtMilliseconds) / 1_000)
    var session =
      sessions[event.sessionID]
      ?? SessionState(
        sessionID: event.sessionID,
        cwd: event.cwd,
        turnID: "session",
        work: .idle,
        result: .none,
        waiting: .none,
        lastPromptAt: nil,
        interventionRequestedAt: nil,
        completedAt: nil,
        updatedAt: timestamp,
        hasUnseenCompletion: false,
        toolFailureCount: 0,
        navigationTarget: nil
      )
    session.cwd = event.cwd
    if let navigationTarget = navigationTarget(for: event) {
      session.navigationTarget = navigationTarget
    }

    switch event.hookEventName {
    case "SessionStart":
      session.work = .idle
      session.waiting = .none
    case "UserPromptSubmit":
      session.turnID = event.recordID.uuidString.lowercased()
      session.work = .running
      session.result = .none
      session.waiting = .none
      session.lastPromptAt = timestamp
      session.interventionRequestedAt = nil
      session.completedAt = nil
      session.hasUnseenCompletion = false
      session.toolFailureCount = 0
    case "PreToolUse", "PostToolUse":
      session.work = .running
      session.waiting = .none
      session.interventionRequestedAt = nil
    case "PostToolUseFailure":
      session.work = .running
      session.waiting = .none
      session.interventionRequestedAt = nil
      session.toolFailureCount += 1
    case "PermissionRequest":
      requestIntervention(.approval, at: timestamp, session: &session)
    case "Elicitation":
      requestIntervention(.answer, at: timestamp, session: &session)
    case "Notification":
      applyNotification(event.notificationType, at: timestamp, session: &session)
    case "Stop":
      guard session.lastPromptAt.map({ timestamp >= $0 }) ?? true else { return }
      session.work = .stopped
      session.result = .completed
      session.waiting = .none
      session.interventionRequestedAt = nil
      session.completedAt = timestamp
      session.hasUnseenCompletion = true
    case "StopFailure":
      guard session.lastPromptAt.map({ timestamp >= $0 }) ?? true else { return }
      session.work = .stopped
      session.result = .failed
      session.completedAt = timestamp
      session.hasUnseenCompletion = true
      session.waiting = .user(.actionableFailure)
      session.interventionRequestedAt = timestamp
    case "SessionEnd":
      session.work = .stopped
      session.waiting = .none
      session.interventionRequestedAt = nil
      if session.result == .none {
        session.result = .unknown
      }
    default:
      return
    }

    session.updatedAt = max(session.updatedAt, timestamp)
    sessions[event.sessionID] = session
  }

  public mutating func reset() {
    sessions.removeAll(keepingCapacity: true)
    appliedRecords.removeAll(keepingCapacity: true)
    appliedRecordOrder.removeAll(keepingCapacity: true)
  }

  private func snapshot(_ session: SessionState) -> AgentTaskSnapshot {
    let title = URL(fileURLWithPath: session.cwd).lastPathComponent
    return AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: provider,
        profileID: profileID,
        dataRoot: dataRoot,
        taskID: session.sessionID,
        executionID: session.sessionID,
        turnID: session.turnID
      ),
      title: title.isEmpty ? "Claude task" : title,
      work: session.work,
      result: session.result,
      waiting: session.waiting,
      lastPromptAt: session.lastPromptAt,
      interventionRequestedAt: session.interventionRequestedAt,
      completedAt: session.completedAt,
      updatedAt: session.updatedAt,
      hasUnseenCompletion: session.hasUnseenCompletion,
      navigationTarget: session.navigationTarget
    )
  }

  private func navigationTarget(for event: StoredClaudeHookEvent) -> TaskNavigationTarget? {
    guard let surface = event.clientSurface,
      let bundleIdentifier = event.applicationBundleIdentifier
    else { return nil }
    switch (surface, bundleIdentifier) {
    case (.desktop, "com.anthropic.claudefordesktop"):
      return TaskNavigationTarget(
        surface: .desktop,
        applicationBundleIdentifier: bundleIdentifier
      )
    case (.terminal, "com.googlecode.iterm2"),
      (.terminal, "com.apple.Terminal"):
      guard event.terminalSessionID != nil || event.tty != nil else { return nil }
      return TaskNavigationTarget(
        surface: .terminal,
        applicationBundleIdentifier: bundleIdentifier,
        terminalSessionID: event.terminalSessionID,
        tty: event.tty
      )
    default:
      return nil
    }
  }

  private func requestIntervention(
    _ kind: InterventionKind,
    at timestamp: Date,
    session: inout SessionState
  ) {
    session.work = .running
    session.waiting = .user(kind)
    session.interventionRequestedAt = timestamp
  }

  private func applyNotification(
    _ notificationType: String?,
    at timestamp: Date,
    session: inout SessionState
  ) {
    switch notificationType {
    case "permission_prompt":
      requestIntervention(.approval, at: timestamp, session: &session)
    case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
      "quota_auto_resume_stale":
      requestIntervention(.answer, at: timestamp, session: &session)
    case "quota_auto_resume_disabled":
      requestIntervention(.actionableFailure, at: timestamp, session: &session)
    default:
      break
    }
  }

  private mutating func trimAppliedRecordsIfNeeded() {
    guard appliedRecordOrder.count > Self.maximumRecentRecordIDs else { return }
    let removed = appliedRecordOrder.prefix(Self.recordIDTrimCount)
    appliedRecords.subtract(removed)
    appliedRecordOrder.removeFirst(Self.recordIDTrimCount)
  }
}

private struct SessionState: Sendable {
  let sessionID: String
  var cwd: String
  var turnID: String
  var work: WorkState
  var result: ResultState
  var waiting: WaitingState
  var lastPromptAt: Date?
  var interventionRequestedAt: Date?
  var completedAt: Date?
  var updatedAt: Date
  var hasUnseenCompletion: Bool
  var toolFailureCount: Int
  var navigationTarget: TaskNavigationTarget?
}
