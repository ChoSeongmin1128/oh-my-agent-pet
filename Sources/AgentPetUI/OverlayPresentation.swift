import AgentPetCore
import Foundation

public enum CardDisplayMode: String, Codable, CaseIterable, Sendable {
  case one
  case many
  case none
}

public enum TaskVisualStatus: String, Equatable, Sendable {
  case inputNeeded
  case working
  case finished
  case failed
  case stopped
  case ready

  public var label: String {
    switch self {
    case .inputNeeded: "Input needed"
    case .working: "Working"
    case .finished: "Finished"
    case .failed: "Failed"
    case .stopped: "Stopped"
    case .ready: "Ready"
    }
  }

  public static func resolve(_ task: AgentTaskSnapshot) -> TaskVisualStatus {
    if task.waiting.requiresUserIntervention { return .inputNeeded }
    switch task.result {
    case .failed: return .failed
    case .interrupted: return .stopped
    case .completed where task.hasUnseenCompletion: return .finished
    default: return task.work == .running ? .working : .ready
    }
  }
}

public struct TaskCardPresentation: Equatable, Sendable {
  public let task: AgentTaskSnapshot
  public let status: TaskVisualStatus
  public let providerLabel: String?
  public let shortTaskID: String?

  public init(
    task: AgentTaskSnapshot,
    status: TaskVisualStatus,
    providerLabel: String?,
    shortTaskID: String?
  ) {
    self.task = task
    self.status = status
    self.providerLabel = providerLabel
    self.shortTaskID = shortTaskID
  }
}

public struct OverlayPresentation: Equatable, Sendable {
  public let cards: [TaskCardPresentation]
  public let petStatus: TaskVisualStatus
  public let additionalInterventionCount: Int
  public let showsPetCompletionDot: Bool
  public let canExpandFromPet: Bool

  public init(
    cards: [TaskCardPresentation],
    petStatus: TaskVisualStatus,
    additionalInterventionCount: Int,
    showsPetCompletionDot: Bool,
    canExpandFromPet: Bool
  ) {
    self.cards = cards
    self.petStatus = petStatus
    self.additionalInterventionCount = additionalInterventionCount
    self.showsPetCompletionDot = showsPetCompletionDot
    self.canExpandFromPet = canExpandFromPet
  }
}

public struct OverlayPresenter: Sendable {
  private let order = TaskPresentationOrder()

  public init() {}

  public func makePresentation(
    tasks: [AgentTaskSnapshot],
    representative: RepresentativeTask?,
    savedMode: CardDisplayMode,
    isTemporarilyExpanded: Bool
  ) -> OverlayPresentation {
    let ordered = order.sorted(tasks)
    let effectiveMode: CardDisplayMode = isTemporarilyExpanded ? .many : savedMode
    let visibleTasks: [AgentTaskSnapshot]
    switch effectiveMode {
    case .one:
      visibleTasks = representative.map { [$0.task] } ?? ordered.prefix(1).map { $0 }
    case .many:
      visibleTasks = ordered
    case .none:
      visibleTasks = []
    }

    let providerCount = Set(ordered.map(\.identity.provider)).count
    let duplicateKeys = Dictionary(grouping: ordered) {
      "\($0.identity.provider.rawValue)\u{1F}\($0.title)"
    }
    let cards = visibleTasks.map { task in
      let duplicateKey = "\(task.identity.provider.rawValue)\u{1F}\(task.title)"
      let hasDuplicate = (duplicateKeys[duplicateKey]?.count ?? 0) > 1
      return TaskCardPresentation(
        task: task,
        status: TaskVisualStatus.resolve(task),
        providerLabel: providerCount > 1 ? providerLabel(task.identity.provider) : nil,
        shortTaskID: hasDuplicate ? String(task.identity.taskID.prefix(6)) : nil
      )
    }

    let visibleIdentities = Set(visibleTasks.map(\.identity))
    let additionalInterventions =
      effectiveMode == .one
      ? ordered.count {
        $0.waiting.requiresUserIntervention && !visibleIdentities.contains($0.identity)
      } : 0
    let petTask = representative?.task ?? ordered.first
    return OverlayPresentation(
      cards: cards,
      petStatus: petTask.map(TaskVisualStatus.resolve) ?? .ready,
      additionalInterventionCount: additionalInterventions,
      showsPetCompletionDot: effectiveMode == .none
        && ordered.contains(where: \.hasUnseenCompletion),
      canExpandFromPet: ordered.count > 1 && savedMode != .many
    )
  }

  private func providerLabel(_ provider: ProviderIdentifier) -> String {
    switch provider.rawValue {
    case "claude": "Claude"
    case "codex": "Codex"
    default: provider.rawValue
    }
  }
}
