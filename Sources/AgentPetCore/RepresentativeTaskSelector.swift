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
  public init() {}

  public func select(from tasks: some Sequence<AgentTaskSnapshot>) -> RepresentativeTask? {
    let candidates = Array(tasks)
    guard !candidates.isEmpty else {
      return nil
    }

    let interventions = candidates.filter { $0.waiting.requiresUserIntervention }
    if let task = preferredTask(
      in: interventions,
      date: { $0.interventionRequestedAt ?? .distantPast }
    ) {
      return RepresentativeTask(task: task, reason: .intervention)
    }

    guard
      let task = preferredTask(
        in: candidates,
        date: { $0.lastPromptAt ?? .distantPast }
      )
    else {
      return nil
    }
    return RepresentativeTask(task: task, reason: .latestPrompt)
  }

  private func preferredTask(
    in tasks: [AgentTaskSnapshot],
    date: (AgentTaskSnapshot) -> Date
  ) -> AgentTaskSnapshot? {
    tasks.max { left, right in
      let leftDate = date(left)
      let rightDate = date(right)
      if leftDate != rightDate {
        return leftDate < rightDate
      }
      return left.identity.stableKey > right.identity.stableKey
    }
  }
}
