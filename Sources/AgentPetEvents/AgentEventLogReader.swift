import Darwin
import Foundation

public enum AgentEventLogReaderError: Error, Equatable, Sendable {
  case readFailed
  case unsafeFile
}

public enum AgentEventLogIssue: Equatable, Sendable {
  case invalidRecord
  case unsupportedSchema
  case oversizedRecord
}

public struct AgentEventReadBatch: Equatable, Sendable {
  public let events: [StoredAgentHookEvent]
  public let issues: [AgentEventLogIssue]
  public let didReset: Bool
  public let reachedEnd: Bool

  public init(
    events: [StoredAgentHookEvent],
    issues: [AgentEventLogIssue],
    didReset: Bool,
    reachedEnd: Bool
  ) {
    self.events = events
    self.issues = issues
    self.didReset = didReset
    self.reachedEnd = reachedEnd
  }
}

public struct AgentEventLogReader: Sendable {
  public static let defaultReadLimit = 1 * 1_024 * 1_024
  public static let maximumRecordBytes = 64 * 1_024

  public let eventsURL: URL

  private var identity: FileIdentity?
  private var offset: off_t = 0
  private var pending = Data()
  private var discardingOversizedRecord = false

  public init(eventsURL: URL) {
    self.eventsURL = eventsURL
  }

  public mutating func readAvailable(
    maximumBytes: Int = Self.defaultReadLimit
  ) throws -> AgentEventReadBatch {
    let descriptor = eventsURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT {
        let reset = identity != nil || offset != 0 || !pending.isEmpty
        resetCursor()
        return AgentEventReadBatch(events: [], issues: [], didReset: reset, reachedEnd: true)
      }
      if errno == ELOOP {
        throw AgentEventLogReaderError.unsafeFile
      }
      throw AgentEventLogReaderError.readFailed
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      throw AgentEventLogReaderError.unsafeFile
    }

    let currentIdentity = FileIdentity(status: fileStatus)
    var didReset = false
    if identity != currentIdentity || fileStatus.st_size < offset {
      didReset = identity != nil
      resetCursor()
      identity = currentIdentity
    } else if identity == nil {
      identity = currentIdentity
    }

    var collectedEvents: [StoredAgentHookEvent] = []
    var collectedIssues: [AgentEventLogIssue] = []
    var bytesRead = 0
    var reachedEnd = false
    let readLimit = max(1, maximumBytes)

    while bytesRead < readLimit {
      let requested = min(64 * 1_024, readLimit - bytesRead)
      var buffer = [UInt8](repeating: 0, count: requested)
      let count = pread(descriptor, &buffer, requested, offset)
      if count < 0 {
        throw AgentEventLogReaderError.readFailed
      }
      if count == 0 {
        reachedEnd = true
        break
      }

      offset += off_t(count)
      bytesRead += count
      let consumed = consume(Data(buffer.prefix(count)))
      collectedEvents.append(contentsOf: consumed.events)
      collectedIssues.append(contentsOf: consumed.issues)
    }

    return AgentEventReadBatch(
      events: collectedEvents,
      issues: collectedIssues,
      didReset: didReset,
      reachedEnd: reachedEnd
    )
  }

  private mutating func consume(_ data: Data) -> (
    events: [StoredAgentHookEvent], issues: [AgentEventLogIssue]
  ) {
    pending.append(data)
    var events: [StoredAgentHookEvent] = []
    var issues: [AgentEventLogIssue] = []
    var scanStart = pending.startIndex

    while true {
      if discardingOversizedRecord {
        guard let newline = pending[scanStart...].firstIndex(of: 0x0A) else {
          scanStart = pending.endIndex
          break
        }
        scanStart = pending.index(after: newline)
        discardingOversizedRecord = false
        continue
      }

      guard let newline = pending[scanStart...].firstIndex(of: 0x0A) else {
        if pending.distance(from: scanStart, to: pending.endIndex) > Self.maximumRecordBytes {
          scanStart = pending.endIndex
          discardingOversizedRecord = true
          issues.append(.oversizedRecord)
        }
        break
      }
      let line = Data(pending[scanStart..<newline])
      scanStart = pending.index(after: newline)

      if line.isEmpty { continue }
      guard line.count <= Self.maximumRecordBytes else {
        issues.append(.oversizedRecord)
        continue
      }
      guard let event = try? JSONDecoder().decode(StoredAgentHookEvent.self, from: line) else {
        issues.append(.invalidRecord)
        continue
      }
      guard StoredAgentHookEvent.supportedSchemaVersions.contains(event.schemaVersion) else {
        issues.append(.unsupportedSchema)
        continue
      }
      events.append(event)
    }

    if scanStart != pending.startIndex {
      pending.removeSubrange(pending.startIndex..<scanStart)
    }
    return (events, issues)
  }

  private mutating func resetCursor() {
    identity = nil
    offset = 0
    pending.removeAll(keepingCapacity: true)
    discardingOversizedRecord = false
  }
}

private struct FileIdentity: Equatable, Sendable {
  let device: UInt64
  let inode: UInt64

  init(status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
  }
}
