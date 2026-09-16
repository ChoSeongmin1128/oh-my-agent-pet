import Foundation

public enum WorkState: String, Codable, Hashable, Sendable {
  case idle
  case running
  case stopped
}

public enum ResultState: String, Codable, Hashable, Sendable {
  case none
  case completed
  case failed
  case unknown
}

public enum InterventionKind: String, Codable, Hashable, Sendable {
  case approval
  case choice
  case answer
  case actionableFailure
}

public enum WaitingState: Codable, Hashable, Sendable {
  case none
  case user(InterventionKind)

  public var requiresUserIntervention: Bool {
    if case .user = self {
      return true
    }
    return false
  }
}

public struct AgentTaskSnapshot: Codable, Hashable, Sendable {
  public let identity: TaskIdentity
  public let title: String
  public let work: WorkState
  public let result: ResultState
  public let waiting: WaitingState
  public let lastPromptAt: Date?
  public let interventionRequestedAt: Date?
  public let completedAt: Date?
  public let updatedAt: Date
  public let hasUnseenCompletion: Bool

  public init(
    identity: TaskIdentity,
    title: String,
    work: WorkState,
    result: ResultState,
    waiting: WaitingState,
    lastPromptAt: Date?,
    interventionRequestedAt: Date?,
    completedAt: Date?,
    updatedAt: Date,
    hasUnseenCompletion: Bool
  ) {
    self.identity = identity
    self.title = title
    self.work = work
    self.result = result
    self.waiting = waiting
    self.lastPromptAt = lastPromptAt
    self.interventionRequestedAt = interventionRequestedAt
    self.completedAt = completedAt
    self.updatedAt = updatedAt
    self.hasUnseenCompletion = hasUnseenCompletion
  }
}
