import AgentPetCore
import AgentPetEvents
import AgentPetProviders
import Foundation

public enum CodexProviderIssue: Equatable, Sendable {
  case sessionIndex(CodexSessionIndexIssue)
  case rollout(CodexRolloutIssue)
  case hookEvent(AgentEventLogIssue)
  case catalog
}

public actor CodexTaskProvider: TaskProviderAdapter {
  public static let defaultMaximumSessions = 32
  private static let maximumRetainedIssues = 128

  public nonisolated let identifier = ProviderIdentifier("codex")!

  private let paths: CodexPaths
  private let maximumSessions: Int
  private var indexReader: CodexSessionIndexReader
  private var eventReader: AgentEventLogReader
  private var hookOverlay = CodexHookOverlayReducer()
  private var trackers: [String: CodexRolloutTracker] = [:]
  private var watchDirectories: [URL] = []
  private var issues: [CodexProviderIssue] = []
  private var catalogLoaded = false

  public init(
    paths: CodexPaths,
    maximumSessions: Int = CodexTaskProvider.defaultMaximumSessions
  ) {
    self.paths = paths
    self.maximumSessions = max(1, maximumSessions)
    indexReader = CodexSessionIndexReader(indexURL: paths.sessionIndexURL)
    eventReader = AgentEventLogReader(eventsURL: paths.eventsURL)
  }

  public func loadTasks() async throws -> [AgentTaskSnapshot] {
    while true {
      let batch = try eventReader.readAvailable()
      if batch.didReset {
        hookOverlay.reset()
      }
      for event in batch.events {
        hookOverlay.apply(event)
      }
      appendIssues(batch.issues.map(CodexProviderIssue.hookEvent))
      if batch.reachedEnd { break }
    }

    let index = try indexReader.readIfChanged()
    if index.didChange {
      appendIssues(index.issues.map(CodexProviderIssue.sessionIndex))
    }

    if index.didChange, catalogLoaded, !index.entries.isEmpty,
      let cachedCandidates = cachedCandidates(for: index.entries)
    {
      reconcile(cachedCandidates)
    } else if index.didChange || !catalogLoaded || index.entries.isEmpty {
      do {
        let catalog = try CodexRolloutCatalog(
          sessionsDirectory: paths.sessionsDirectory,
          maximumSessions: maximumSessions
        ).discover(indexEntries: index.entries)
        reconcile(catalog.candidates)
        watchDirectories = catalog.watchDirectories
        catalogLoaded = true
      } catch {
        appendIssues([.catalog])
        if !catalogLoaded { throw error }
      }
    }

    var snapshots: [AgentTaskSnapshot] = []
    for sessionID in trackers.keys.sorted() {
      guard var tracker = trackers[sessionID] else { continue }
      let refresh = tracker.refresh()
      trackers[sessionID] = tracker
      appendIssues(refresh.issues.map(CodexProviderIssue.rollout))
      if let snapshot = refresh.snapshot {
        snapshots.append(hookOverlay.applying(to: snapshot))
      }
    }
    return snapshots.sorted { $0.identity.stableKey < $1.identity.stableKey }
  }

  public func watchedURLs() -> [URL] {
    var urls = Set(watchDirectories)
    urls.insert(paths.dataRoot)
    urls.insert(paths.sessionsDirectory)
    urls.insert(paths.sessionIndexURL)
    for tracker in trackers.values {
      urls.insert(tracker.candidate.rolloutURL)
    }
    return urls.sorted { $0.path < $1.path }
  }

  public func currentIssues() -> [CodexProviderIssue] {
    issues
  }

  private func reconcile(_ candidates: [CodexRolloutCandidate]) {
    var next: [String: CodexRolloutTracker] = [:]
    for candidate in candidates {
      if var tracker = trackers[candidate.sessionID],
        tracker.candidate.rolloutURL == candidate.rolloutURL
      {
        tracker.update(candidate: candidate)
        next[candidate.sessionID] = tracker
      } else {
        next[candidate.sessionID] = CodexRolloutTracker(
          candidate: candidate,
          dataRoot: paths.dataRoot.path
        )
      }
    }
    trackers = next
  }

  private func cachedCandidates(
    for entries: [CodexSessionIndexEntry]
  ) -> [CodexRolloutCandidate]? {
    let desired = Array(entries.prefix(maximumSessions))
    var candidates: [CodexRolloutCandidate] = []
    for entry in desired {
      guard let tracker = trackers[entry.id] else { return nil }
      candidates.append(
        CodexRolloutCandidate(
          sessionID: entry.id,
          title: entry.title,
          indexUpdatedAt: entry.updatedAt,
          rolloutURL: tracker.candidate.rolloutURL
        ))
    }
    return candidates
  }

  private func appendIssues(_ newIssues: [CodexProviderIssue]) {
    issues.append(contentsOf: newIssues)
    if issues.count > Self.maximumRetainedIssues {
      issues.removeFirst(issues.count - Self.maximumRetainedIssues)
    }
  }
}
