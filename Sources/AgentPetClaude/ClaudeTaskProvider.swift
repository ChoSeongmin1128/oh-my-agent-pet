import AgentPetCore
import AgentPetProviders
import Foundation

public actor ClaudeTaskProvider: TaskProviderAdapter {
  private static let maximumRetainedIssues = 128

  public nonisolated let identifier = ProviderIdentifier("claude")!

  private var reader: ClaudeEventLogReader
  private var reducer: ClaudeEventReducer
  private var issues: [ClaudeEventLogIssue] = []

  public init(paths: ClaudePaths, profileID: String = "default") {
    reader = ClaudeEventLogReader(eventsURL: paths.eventsURL)
    reducer = ClaudeEventReducer(profileID: profileID, dataRoot: paths.configRoot.path)
  }

  public func loadTasks() async throws -> [AgentTaskSnapshot] {
    while true {
      let batch = try reader.readAvailable()
      if batch.didReset {
        reducer.reset()
        issues.removeAll(keepingCapacity: true)
      }
      for event in batch.events {
        reducer.apply(event)
      }
      issues.append(contentsOf: batch.issues)
      if issues.count > Self.maximumRetainedIssues {
        issues.removeFirst(issues.count - Self.maximumRetainedIssues)
      }
      if batch.reachedEnd {
        break
      }
    }
    return reducer.snapshots
  }

  public func currentIssues() -> [ClaudeEventLogIssue] {
    issues
  }
}
