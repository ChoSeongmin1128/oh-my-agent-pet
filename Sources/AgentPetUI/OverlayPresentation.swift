import AgentPetCore
import Foundation

public enum CardDisplayMode: String, Codable, CaseIterable, Sendable {
  case one
  case many
  case none
}

enum CardDepthHintPolicy {
  static let maximumLayers = 2
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
  public let cardDepthLayerCount: Int
  public let showsPetCompletionDot: Bool
  public let canToggleExpansion: Bool
  public let isTemporarilyExpanded: Bool

  public init(
    cards: [TaskCardPresentation],
    petStatus: TaskVisualStatus,
    additionalInterventionCount: Int,
    cardDepthLayerCount: Int = 0,
    showsPetCompletionDot: Bool,
    canToggleExpansion: Bool,
    isTemporarilyExpanded: Bool
  ) {
    self.cards = cards
    self.petStatus = petStatus
    self.additionalInterventionCount = additionalInterventionCount
    self.cardDepthLayerCount = cardDepthLayerCount
    self.showsPetCompletionDot = showsPetCompletionDot
    self.canToggleExpansion = canToggleExpansion
    self.isTemporarilyExpanded = isTemporarilyExpanded
  }

  public static func preview(status: TaskVisualStatus) -> OverlayPresentation {
    OverlayPresentation(
      cards: [],
      petStatus: status,
      additionalInterventionCount: 0,
      cardDepthLayerCount: 0,
      showsPetCompletionDot: false,
      canToggleExpansion: false,
      isTemporarilyExpanded: false
    )
  }
}

public struct OverlayPresenter: Sendable {
  private let order = TaskPresentationOrder()

  public init() {}

  public func makePresentation(
    tasks: [AgentTaskSnapshot],
    representative: RepresentativeTask?,
    savedMode: CardDisplayMode,
    isTemporarilyExpanded: Bool,
    connectedProviderCount: Int? = nil
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

    let providerCount =
      connectedProviderCount ?? Set(ordered.map(\.identity.provider)).count
    let duplicateKeys = Dictionary(grouping: ordered) {
      "\($0.identity.provider.rawValue)\u{1F}\($0.title)"
    }
    let cards = visibleTasks.map { task in
      let duplicateKey = "\(task.identity.provider.rawValue)\u{1F}\(task.title)"
      let hasDuplicate = (duplicateKeys[duplicateKey]?.count ?? 0) > 1
      return TaskCardPresentation(
        task: task,
        status: TaskVisualStatus.resolve(task),
        providerLabel: providerCount > 1 ? task.identity.provider.displayName : nil,
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
    let cardDepthLayerCount =
      effectiveMode == .one && !visibleTasks.isEmpty
      ? min(max(ordered.count - visibleTasks.count, 0), CardDepthHintPolicy.maximumLayers)
      : 0
    return OverlayPresentation(
      cards: cards,
      petStatus: petTask.map(TaskVisualStatus.resolve) ?? .ready,
      additionalInterventionCount: additionalInterventions,
      cardDepthLayerCount: cardDepthLayerCount,
      showsPetCompletionDot: effectiveMode == .none
        && ordered.contains(where: \.hasUnseenCompletion),
      canToggleExpansion: ordered.count > 1 && savedMode != .many,
      isTemporarilyExpanded: isTemporarilyExpanded && ordered.count > 1
    )
  }

}
