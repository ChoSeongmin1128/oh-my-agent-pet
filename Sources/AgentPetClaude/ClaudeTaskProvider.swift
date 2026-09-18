import AgentPetCore
import AgentPetProviders
import Foundation

public actor ClaudeTaskProvider: TaskProviderAdapter {
  private static let maximumRetainedIssues = 128

  public nonisolated let identifier = ProviderIdentifier.claude

  private var reader: ClaudeEventLogReader
  private var reducer: ClaudeEventReducer
  private var issues: [ClaudeEventLogIssue] = []
  private var desktopSessionIndex: ClaudeDesktopSessionIndex
  private let desktopSessionsDirectory: URL

  public init(paths: ClaudePaths, profileID: String = "default") {
    reader = ClaudeEventLogReader(eventsURL: paths.eventsURL)
    reducer = ClaudeEventReducer(profileID: profileID, dataRoot: paths.configRoot.path)
    desktopSessionIndex = ClaudeDesktopSessionIndex(
      sessionsDirectory: paths.desktopSessionsDirectory
    )
    desktopSessionsDirectory = paths.desktopSessionsDirectory
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
    let snapshots = reducer.snapshots
    guard !snapshots.isEmpty else { return [] }
    let desktopRoutes = desktopSessionIndex.routes()
    return snapshots.map { snapshot in
      if snapshot.navigationTarget?.surface == .terminal {
        return snapshot
      }
      guard let desktopSessionID = desktopRoutes[snapshot.identity.taskID] else {
        return snapshot
      }
      let deepLink = "claude://code/continue?session=\(desktopSessionID)"
      return snapshot.replacingNavigationTarget(
        TaskNavigationTarget(
          surface: .desktop,
          applicationBundleIdentifier: "com.anthropic.claudefordesktop",
          deepLink: deepLink
        )
      )
    }
  }

  public func currentIssues() -> [ClaudeEventLogIssue] {
    issues
  }

  public func watchedURLs() async -> [URL] {
    [
      desktopSessionsDirectory.deletingLastPathComponent(),
      desktopSessionsDirectory,
    ]
  }
}
