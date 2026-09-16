import Foundation

public struct TaskCatalog: Sendable {
  private var snapshots: [TaskIdentity: AgentTaskSnapshot]

  public init() {
    snapshots = [:]
  }

  public init(_ tasks: some Sequence<AgentTaskSnapshot>) {
    snapshots = Dictionary(
      tasks.map { ($0.identity, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  public var tasks: [AgentTaskSnapshot] {
    snapshots.values.sorted { $0.identity.stableKey < $1.identity.stableKey }
  }

  public mutating func replaceAll(with tasks: some Sequence<AgentTaskSnapshot>) {
    snapshots = Dictionary(
      tasks.map { ($0.identity, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  public mutating func upsert(_ task: AgentTaskSnapshot) {
    snapshots[task.identity] = task
  }

  public mutating func remove(_ identity: TaskIdentity) {
    snapshots.removeValue(forKey: identity)
  }

  public subscript(identity: TaskIdentity) -> AgentTaskSnapshot? {
    snapshots[identity]
  }
}
