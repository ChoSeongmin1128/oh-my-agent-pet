import AgentPetCore
import AgentPetEvents
import Foundation

struct CodexHookOverlayReducer: Sendable {
  private static let maximumRecentRecordIDs = 4_096
  private static let recordIDTrimCount = 1_024

  private var sessions: [String: WaitingOverlay] = [:]
  private var appliedRecords: Set<UUID> = []
  private var appliedRecordOrder: [UUID] = []

  mutating func apply(_ event: StoredAgentHookEvent) {
    guard event.provider == .codex else { return }
    guard appliedRecords.insert(event.recordID).inserted else { return }
    appliedRecordOrder.append(event.recordID)
    trimAppliedRecordsIfNeeded()

    let sessionID = event.sessionID.lowercased()
    let timestamp = Date(timeIntervalSince1970: Double(event.receivedAtMilliseconds) / 1_000)
    var overlay =
      sessions[sessionID]
      ?? WaitingOverlay(
        turnID: nil,
        waiting: .none,
        interventionRequestedAt: nil,
        updatedAt: .distantPast,
        navigationTarget: nil
      )
    guard timestamp >= overlay.updatedAt else { return }
    if let navigationTarget = navigationTarget(for: event) {
      overlay.navigationTarget = navigationTarget
    }

    switch event.hookEventName {
    case "PermissionRequest":
      overlay.turnID = event.turnID
      overlay.waiting = .user(.approval)
      overlay.interventionRequestedAt = timestamp
    case "UserPromptSubmit", "SessionStart":
      overlay.turnID = event.turnID
      clear(&overlay)
    case "PreToolUse", "PostToolUse", "Stop", "Interrupt", "SessionEnd":
      guard matchesCurrentTurn(event.turnID, overlay.turnID) else { return }
      clear(&overlay)
    default:
      return
    }
    overlay.updatedAt = timestamp
    sessions[sessionID] = overlay
  }

  mutating func reset() {
    sessions.removeAll(keepingCapacity: true)
    appliedRecords.removeAll(keepingCapacity: true)
    appliedRecordOrder.removeAll(keepingCapacity: true)
  }

  func applying(to snapshot: AgentTaskSnapshot) -> AgentTaskSnapshot {
    guard snapshot.identity.provider == .codex,
      let overlay = sessions[snapshot.identity.taskID.lowercased()],
      overlay.navigationTarget != nil || overlay.waiting.requiresUserIntervention
    else {
      return snapshot
    }
    let navigationTarget = overlay.navigationTarget ?? snapshot.navigationTarget
    guard snapshot.work == .running,
      overlay.waiting.requiresUserIntervention,
      matchesCurrentTurn(overlay.turnID, snapshot.identity.turnID),
      overlay.interventionRequestedAt.map({ requestedAt in
        snapshot.lastPromptAt.map { requestedAt >= $0 } ?? true
      }) ?? false
    else {
      return snapshot.replacingNavigationTarget(navigationTarget)
    }

    return AgentTaskSnapshot(
      identity: snapshot.identity,
      title: snapshot.title,
      work: snapshot.work,
      result: snapshot.result,
      waiting: overlay.waiting,
      lastPromptAt: snapshot.lastPromptAt,
      interventionRequestedAt: overlay.interventionRequestedAt,
      completedAt: snapshot.completedAt,
      updatedAt: max(snapshot.updatedAt, overlay.updatedAt),
      hasUnseenCompletion: snapshot.hasUnseenCompletion,
      navigationTarget: navigationTarget
    )
  }

  private func navigationTarget(for event: StoredAgentHookEvent) -> TaskNavigationTarget? {
    guard let surface = event.clientSurface,
      let bundleIdentifier = event.applicationBundleIdentifier
    else { return nil }
    switch (surface, bundleIdentifier) {
    case (.desktop, "com.openai.codex"):
      guard UUID(uuidString: event.sessionID) != nil else { return nil }
      return TaskNavigationTarget(
        surface: .desktop,
        applicationBundleIdentifier: bundleIdentifier,
        deepLink: "codex://threads/\(event.sessionID.lowercased())"
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

  private func matchesCurrentTurn(_ first: String?, _ second: String?) -> Bool {
    guard let first, !first.isEmpty, let second, !second.isEmpty, second != "session" else {
      return true
    }
    return first == second
  }

  private func clear(_ overlay: inout WaitingOverlay) {
    overlay.waiting = .none
    overlay.interventionRequestedAt = nil
  }

  private mutating func trimAppliedRecordsIfNeeded() {
    guard appliedRecordOrder.count > Self.maximumRecentRecordIDs else { return }
    let removed = appliedRecordOrder.prefix(Self.recordIDTrimCount)
    appliedRecords.subtract(removed)
    appliedRecordOrder.removeFirst(Self.recordIDTrimCount)
  }
}

private struct WaitingOverlay: Sendable {
  var turnID: String?
  var waiting: WaitingState
  var interventionRequestedAt: Date?
  var updatedAt: Date
  var navigationTarget: TaskNavigationTarget?
}
