import Foundation

public enum RepresentativeSelectionReason: String, Codable, Hashable, Sendable {
  case intervention
  case latestPrompt
}

public struct RepresentativeTask: Codable, Hashable, Sendable {
  public let task: AgentTaskSnapshot
  public let reason: RepresentativeSelectionReason

  public init(task: AgentTaskSnapshot, reason: RepresentativeSelectionReason) {
    self.task = task
    self.reason = reason
  }
}

public struct RepresentativeTaskSelector: Sendable {
  private let order = TaskPresentationOrder()

  public init() {}

  public func select(from tasks: some Sequence<AgentTaskSnapshot>) -> RepresentativeTask? {
    guard let task = order.sorted(tasks).first else { return nil }
    if task.waiting.requiresUserIntervention {
      return RepresentativeTask(task: task, reason: .intervention)
    }
    return RepresentativeTask(task: task, reason: .latestPrompt)
  }
}
