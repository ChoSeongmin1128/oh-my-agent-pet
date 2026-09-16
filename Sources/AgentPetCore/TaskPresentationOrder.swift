import Foundation

public struct TaskPresentationOrder: Sendable {
  public init() {}

  public func sorted(_ tasks: some Sequence<AgentTaskSnapshot>) -> [AgentTaskSnapshot] {
    Array(tasks).sorted(by: comesBefore)
  }

  private func comesBefore(_ left: AgentTaskSnapshot, _ right: AgentTaskSnapshot) -> Bool {
    let leftNeedsInput = left.waiting.requiresUserIntervention
    let rightNeedsInput = right.waiting.requiresUserIntervention
    if leftNeedsInput != rightNeedsInput {
      return leftNeedsInput
    }

    let leftDate =
      leftNeedsInput
      ? left.interventionRequestedAt ?? .distantPast : left.lastPromptAt ?? .distantPast
    let rightDate =
      rightNeedsInput
      ? right.interventionRequestedAt ?? .distantPast : right.lastPromptAt ?? .distantPast
    if leftDate != rightDate {
      return leftDate > rightDate
    }
    return left.identity.stableKey < right.identity.stableKey
  }
}
