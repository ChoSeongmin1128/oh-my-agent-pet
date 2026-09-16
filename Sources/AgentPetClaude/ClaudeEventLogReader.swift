import Darwin
import Foundation

public enum ClaudeEventLogIssue: String, Equatable, Sendable {
  case invalidRecord
  case oversizedRecord
  case unsupportedSchema
}

public enum ClaudeEventLogReaderError: Error, Equatable, Sendable {
  case unsafeFile
  case readFailed
}

public struct ClaudeEventReadBatch: Equatable, Sendable {
  public let events: [StoredClaudeHookEvent]
  public let issues: [ClaudeEventLogIssue]
  public let didReset: Bool
  public let reachedEnd: Bool

  public init(
    events: [StoredClaudeHookEvent],
    issues: [ClaudeEventLogIssue],
    didReset: Bool,
    reachedEnd: Bool
  ) {
    self.events = events
    self.issues = issues
    self.didReset = didReset
    self.reachedEnd = reachedEnd
  }
}

public struct ClaudeEventLogReader: Sendable {
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
  ) throws -> ClaudeEventReadBatch {
    let descriptor = eventsURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT {
        let reset = identity != nil || offset != 0 || !pending.isEmpty
        resetCursor()
        return ClaudeEventReadBatch(events: [], issues: [], didReset: reset, reachedEnd: true)
      }
      if errno == ELOOP {
        throw ClaudeEventLogReaderError.unsafeFile
      }
      throw ClaudeEventLogReaderError.readFailed
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      throw ClaudeEventLogReaderError.unsafeFile
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

    var collectedEvents: [StoredClaudeHookEvent] = []
    var collectedIssues: [ClaudeEventLogIssue] = []
    var bytesRead = 0
    var reachedEnd = false
    let readLimit = max(1, maximumBytes)

    while bytesRead < readLimit {
      let requested = min(64 * 1_024, readLimit - bytesRead)
      var buffer = [UInt8](repeating: 0, count: requested)
      let count = pread(descriptor, &buffer, requested, offset)
      if count < 0 {
        throw ClaudeEventLogReaderError.readFailed
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

    return ClaudeEventReadBatch(
      events: collectedEvents,
      issues: collectedIssues,
      didReset: didReset,
      reachedEnd: reachedEnd
    )
  }

  private mutating func consume(_ data: Data) -> (
    events: [StoredClaudeHookEvent], issues: [ClaudeEventLogIssue]
  ) {
    pending.append(data)
    var events: [StoredClaudeHookEvent] = []
    var issues: [ClaudeEventLogIssue] = []
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

      if line.isEmpty {
        continue
      }
      guard line.count <= Self.maximumRecordBytes else {
        issues.append(.oversizedRecord)
        continue
      }
      guard let event = try? JSONDecoder().decode(StoredClaudeHookEvent.self, from: line) else {
        issues.append(.invalidRecord)
        continue
      }
      guard event.schemaVersion == StoredClaudeHookEvent.currentSchemaVersion else {
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
