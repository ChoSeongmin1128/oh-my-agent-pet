import AgentPetCore
import Darwin
import Foundation

public enum CodexRolloutIssue: String, Equatable, Sendable {
  case invalidRecord
  case oversizedRecord
  case unsafeFile
  case readFailed
}

struct CodexRolloutRefresh {
  let snapshot: AgentTaskSnapshot?
  let issues: [CodexRolloutIssue]
  let didReset: Bool
}

struct CodexRolloutTracker {
  static let maximumRecordBytes = 8 * 1_024 * 1_024
  static let maximumInitialScanBytes = 64 * 1_024 * 1_024
  static let defaultReadLimit = 1 * 1_024 * 1_024
  private static let taskStartedNeedle = Array("\"task_started\"".utf8)
  private static let taskCompleteNeedle = Array("\"task_complete\"".utf8)
  private static let turnAbortedNeedle = Array("\"turn_aborted\"".utf8)

  private let provider = ProviderIdentifier.codex
  private let dataRoot: String
  private let dateParser = CodexDateParser()
  private(set) var candidate: CodexRolloutCandidate

  private var identity: CodexRolloutFileIdentity?
  private var offset: off_t = 0
  private var pending = Data()
  private var discardingOversizedRecord = false
  private var state: CodexRolloutState?

  init(candidate: CodexRolloutCandidate, dataRoot: String) {
    self.candidate = candidate
    self.dataRoot = dataRoot
  }

  mutating func update(candidate: CodexRolloutCandidate) {
    self.candidate = candidate
    state?.title = candidate.title
    state?.indexUpdatedAt = candidate.indexUpdatedAt
  }

  mutating func refresh() -> CodexRolloutRefresh {
    let descriptor = candidate.rolloutURL.withUnsafeFileSystemRepresentation { filePath -> Int32 in
      guard let filePath else { return -1 }
      return Darwin.open(filePath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      let issue: CodexRolloutIssue = errno == ELOOP ? .unsafeFile : .readFailed
      return CodexRolloutRefresh(snapshot: nil, issues: [issue], didReset: false)
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      return CodexRolloutRefresh(snapshot: nil, issues: [.unsafeFile], didReset: false)
    }

    let currentIdentity = CodexRolloutFileIdentity(status: fileStatus)
    if identity != currentIdentity || fileStatus.st_size < offset {
      let didReset = identity != nil
      let issues = loadInitial(descriptor: descriptor, fileStatus: fileStatus)
      return CodexRolloutRefresh(snapshot: snapshot(), issues: issues, didReset: didReset)
    }

    let issues = readAppended(descriptor: descriptor)
    return CodexRolloutRefresh(snapshot: snapshot(), issues: issues, didReset: false)
  }

  private mutating func loadInitial(descriptor: Int32, fileStatus: stat) -> [CodexRolloutIssue] {
    identity = CodexRolloutFileIdentity(status: fileStatus)
    offset = fileStatus.st_size
    pending.removeAll(keepingCapacity: true)
    discardingOversizedRecord = false
    state = CodexRolloutState(
      sessionID: candidate.sessionID,
      title: candidate.title,
      cwd: "",
      turnID: "session",
      work: .idle,
      result: .none,
      lastPromptAt: nil,
      completedAt: nil,
      updatedAt: candidate.indexUpdatedAt,
      indexUpdatedAt: candidate.indexUpdatedAt,
      hasUnseenCompletion: false,
      navigationTarget: nil
    )

    guard fileStatus.st_size > 0 else { return [] }
    let mapped = mmap(nil, Int(fileStatus.st_size), PROT_READ, MAP_PRIVATE, descriptor, 0)
    guard mapped != MAP_FAILED, let mapped else { return [.readFailed] }
    defer { munmap(mapped, Int(fileStatus.st_size)) }

    let bytes = UnsafeRawPointer(mapped).assumingMemoryBound(to: UInt8.self)
    let size = Int(fileStatus.st_size)
    var issues: [CodexRolloutIssue] = []

    if let firstLine = completeFirstLine(bytes: bytes, size: size),
      firstLine.count <= Self.maximumRecordBytes
    {
      applyMetadata(Data(bytes: bytes + firstLine.start, count: firstLine.count))
    }

    let trailing = trailingPartial(bytes: bytes, size: size)
    if trailing.count > Self.maximumRecordBytes {
      discardingOversizedRecord = true
      issues.append(.oversizedRecord)
    } else if trailing.count > 0 {
      pending = Data(bytes: bytes + trailing.start, count: trailing.count)
    }

    if let lifecycle = lastLifecycleRecord(bytes: bytes, completeEnd: trailing.completeEnd) {
      apply(lifecycle, isInitial: true)
    }
    return issues
  }

  private mutating func readAppended(descriptor: Int32) -> [CodexRolloutIssue] {
    var issues: [CodexRolloutIssue] = []
    while true {
      var buffer = [UInt8](repeating: 0, count: Self.defaultReadLimit)
      let count = pread(descriptor, &buffer, buffer.count, offset)
      if count < 0 {
        issues.append(.readFailed)
        break
      }
      if count == 0 { break }
      offset += off_t(count)
      issues.append(contentsOf: consume(Data(buffer.prefix(count))))
      if count < buffer.count { break }
    }
    return issues
  }

  private mutating func consume(_ data: Data) -> [CodexRolloutIssue] {
    pending.append(data)
    var issues: [CodexRolloutIssue] = []
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
      guard !line.isEmpty else { continue }
      guard line.count <= Self.maximumRecordBytes else {
        issues.append(.oversizedRecord)
        continue
      }
      guard isRelevant(line) else { continue }
      if line.range(of: Data("\"session_meta\"".utf8)) != nil {
        applyMetadata(line)
      } else if let record = decodeLifecycle(line) {
        apply(record, isInitial: false)
      } else {
        issues.append(.invalidRecord)
      }
    }

    if scanStart != pending.startIndex {
      pending.removeSubrange(pending.startIndex..<scanStart)
    }
    return issues
  }

  private func snapshot() -> AgentTaskSnapshot? {
    guard let state else { return nil }
    let fallbackTitle = URL(fileURLWithPath: state.cwd).lastPathComponent
    let title = state.title ?? (fallbackTitle.isEmpty ? "Codex task" : fallbackTitle)
    return AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: provider,
        profileID: "default",
        dataRoot: dataRoot,
        taskID: state.sessionID,
        executionID: state.sessionID,
        turnID: state.turnID
      ),
      title: title,
      work: state.work,
      result: state.result,
      waiting: .none,
      lastPromptAt: state.lastPromptAt,
      interventionRequestedAt: nil,
      completedAt: state.completedAt,
      updatedAt: max(state.updatedAt, state.indexUpdatedAt),
      hasUnseenCompletion: state.hasUnseenCompletion,
      navigationTarget: state.navigationTarget
    )
  }

  private mutating func applyMetadata(_ line: Data) {
    guard let metadata = try? JSONDecoder().decode(CodexMetadataEnvelope.self, from: line),
      metadata.type == "session_meta"
    else { return }
    if let id = metadata.payload.id ?? metadata.payload.sessionID, !id.isEmpty {
      state?.sessionID = id.lowercased()
    }
    if let cwd = metadata.payload.cwd {
      state?.cwd = cwd
    }
    if let sessionID = state?.sessionID,
      UUID(uuidString: sessionID) != nil,
      metadata.payload.originator == "Codex Desktop"
        || metadata.payload.originator == "codex_work_desktop"
    {
      state?.navigationTarget = TaskNavigationTarget(
        surface: .desktop,
        applicationBundleIdentifier: "com.openai.codex",
        deepLink: "codex://threads/\(sessionID)"
      )
    }
  }

  private mutating func apply(_ record: CodexLifecycleRecord, isInitial: Bool) {
    guard var state else { return }
    let timestamp = dateParser.parse(record.timestamp) ?? state.indexUpdatedAt
    switch record.type {
    case "task_started":
      state.turnID = record.turnID ?? "turn-\(Int(timestamp.timeIntervalSince1970 * 1_000))"
      state.work = .running
      state.result = .none
      state.lastPromptAt = timestamp
      state.completedAt = nil
      state.hasUnseenCompletion = false
    case "task_complete":
      guard record.turnID == nil || record.turnID == state.turnID || state.work != .running else {
        return
      }
      if let turnID = record.turnID { state.turnID = turnID }
      state.work = .stopped
      state.result = .completed
      state.completedAt = timestamp
      state.hasUnseenCompletion = !isInitial
    case "turn_aborted":
      guard record.turnID == nil || record.turnID == state.turnID || state.work != .running else {
        return
      }
      if let turnID = record.turnID { state.turnID = turnID }
      state.work = .stopped
      state.result = .interrupted
      state.completedAt = timestamp
      state.hasUnseenCompletion = false
    default:
      return
    }
    state.updatedAt = max(state.updatedAt, timestamp)
    self.state = state
  }

  private func lastLifecycleRecord(
    bytes: UnsafePointer<UInt8>,
    completeEnd: Int
  ) -> CodexLifecycleRecord? {
    var cursor = completeEnd
    let minimumCursor = max(0, completeEnd - Self.maximumInitialScanBytes)
    while cursor > minimumCursor {
      if bytes[cursor - 1] == 0x0A { cursor -= 1 }
      let lineEnd = cursor
      while cursor > minimumCursor, bytes[cursor - 1] != 0x0A { cursor -= 1 }
      let lineLength = lineEnd - cursor
      guard lineLength > 0 else { continue }
      if lineLength <= Self.maximumRecordBytes,
        containsLifecycleMarker(bytes: bytes + cursor, count: lineLength)
      {
        let line = Data(bytes: bytes + cursor, count: lineLength)
        if let record = decodeLifecycle(line) { return record }
      }
    }
    return nil
  }

  private func decodeLifecycle(_ line: Data) -> CodexLifecycleRecord? {
    guard
      let envelope = try? JSONDecoder().decode(CodexLifecycleEnvelope.self, from: line),
      envelope.type == "event_msg",
      ["task_started", "task_complete", "turn_aborted"].contains(envelope.payload.type)
    else { return nil }
    return CodexLifecycleRecord(
      timestamp: envelope.timestamp,
      type: envelope.payload.type,
      turnID: envelope.payload.turnID
    )
  }

  private func isRelevant(_ line: Data) -> Bool {
    if line.range(of: Data("\"type\":\"session_meta\"".utf8)) != nil {
      return true
    }
    guard line.range(of: Data("\"type\":\"event_msg\"".utf8)) != nil else {
      return false
    }
    return line.range(of: Data("\"task_started\"".utf8)) != nil
      || line.range(of: Data("\"task_complete\"".utf8)) != nil
      || line.range(of: Data("\"turn_aborted\"".utf8)) != nil
  }

  private func containsLifecycleMarker(bytes: UnsafePointer<UInt8>, count: Int) -> Bool {
    contains(Self.taskStartedNeedle, bytes: bytes, count: count)
      || contains(Self.taskCompleteNeedle, bytes: bytes, count: count)
      || contains(Self.turnAbortedNeedle, bytes: bytes, count: count)
  }

  private func contains(
    _ needle: [UInt8],
    bytes: UnsafePointer<UInt8>,
    count: Int
  ) -> Bool {
    guard count >= needle.count else { return false }
    for start in 0...(count - needle.count) where bytes[start] == needle[0] {
      var matches = true
      for index in 1..<needle.count where bytes[start + index] != needle[index] {
        matches = false
        break
      }
      if matches { return true }
    }
    return false
  }

  private func completeFirstLine(
    bytes: UnsafePointer<UInt8>,
    size: Int
  ) -> (start: Int, count: Int)? {
    var end = 0
    while end < size, bytes[end] != 0x0A, end <= Self.maximumRecordBytes { end += 1 }
    guard end < size, bytes[end] == 0x0A else { return nil }
    return (0, end)
  }

  private func trailingPartial(
    bytes: UnsafePointer<UInt8>,
    size: Int
  ) -> (start: Int, count: Int, completeEnd: Int) {
    guard size > 0, bytes[size - 1] != 0x0A else { return (size, 0, size) }
    var start = size
    while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
    return (start, size - start, start)
  }
}

private struct CodexRolloutFileIdentity: Equatable {
  let device: UInt64
  let inode: UInt64

  init(status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
  }
}

private struct CodexRolloutState {
  var sessionID: String
  var title: String?
  var cwd: String
  var turnID: String
  var work: WorkState
  var result: ResultState
  var lastPromptAt: Date?
  var completedAt: Date?
  var updatedAt: Date
  var indexUpdatedAt: Date
  var hasUnseenCompletion: Bool
  var navigationTarget: TaskNavigationTarget?
}

private struct CodexMetadataEnvelope: Decodable {
  let type: String
  let payload: Payload

  struct Payload: Decodable {
    let id: String?
    let sessionID: String?
    let cwd: String?
    let originator: String?

    enum CodingKeys: String, CodingKey {
      case id
      case sessionID = "session_id"
      case cwd
      case originator
    }
  }
}

private struct CodexLifecycleEnvelope: Decodable {
  let timestamp: String?
  let type: String
  let payload: Payload

  struct Payload: Decodable {
    let type: String
    let turnID: String?

    enum CodingKeys: String, CodingKey {
      case type
      case turnID = "turn_id"
    }
  }
}

private struct CodexLifecycleRecord {
  let timestamp: String?
  let type: String
  let turnID: String?
}
