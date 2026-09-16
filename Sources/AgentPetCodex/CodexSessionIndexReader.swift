import Darwin
import Foundation

public enum CodexSessionIndexIssue: String, Equatable, Sendable {
  case invalidRecord
  case oversizedFile
}

public enum CodexSessionIndexError: Error, Equatable, Sendable {
  case unsafeFile
  case readFailed
}

public struct CodexSessionIndexEntry: Equatable, Sendable {
  public let id: String
  public let title: String
  public let updatedAt: Date

  public init(id: String, title: String, updatedAt: Date) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
  }
}

public struct CodexSessionIndexReadResult: Equatable, Sendable {
  public let entries: [CodexSessionIndexEntry]
  public let issues: [CodexSessionIndexIssue]
  public let didChange: Bool
}

public struct CodexSessionIndexReader: Sendable {
  public static let maximumFileBytes = 8 * 1_024 * 1_024
  public static let maximumRecordBytes = 64 * 1_024

  public let indexURL: URL

  private var signature: CodexFileSignature?
  private var cachedEntries: [CodexSessionIndexEntry] = []
  private var cachedIssues: [CodexSessionIndexIssue] = []
  private var hasRead = false

  public init(indexURL: URL) {
    self.indexURL = indexURL
  }

  public mutating func readIfChanged() throws -> CodexSessionIndexReadResult {
    let descriptor = indexURL.withUnsafeFileSystemRepresentation { filePath -> Int32 in
      guard let filePath else { return -1 }
      return Darwin.open(filePath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT {
        let changed = !hasRead || signature != nil || !cachedEntries.isEmpty
        signature = nil
        cachedEntries = []
        cachedIssues = []
        hasRead = true
        return CodexSessionIndexReadResult(entries: [], issues: [], didChange: changed)
      }
      if errno == ELOOP {
        throw CodexSessionIndexError.unsafeFile
      }
      throw CodexSessionIndexError.readFailed
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      throw CodexSessionIndexError.unsafeFile
    }

    let currentSignature = CodexFileSignature(status: fileStatus)
    if hasRead, signature == currentSignature {
      return CodexSessionIndexReadResult(
        entries: cachedEntries,
        issues: cachedIssues,
        didChange: false
      )
    }

    hasRead = true
    signature = currentSignature
    guard fileStatus.st_size <= Self.maximumFileBytes else {
      cachedEntries = []
      cachedIssues = [.oversizedFile]
      return CodexSessionIndexReadResult(
        entries: [], issues: cachedIssues, didChange: true)
    }

    let data = try read(descriptor: descriptor, count: Int(fileStatus.st_size))
    let parsed = parse(data)
    cachedEntries = parsed.entries
    cachedIssues = parsed.issues
    return CodexSessionIndexReadResult(
      entries: cachedEntries,
      issues: cachedIssues,
      didChange: true
    )
  }

  private func read(descriptor: Int32, count: Int) throws -> Data {
    guard count > 0 else { return Data() }
    var data = Data(count: count)
    let bytesRead = data.withUnsafeMutableBytes { buffer -> Int in
      guard let address = buffer.baseAddress else { return 0 }
      return pread(descriptor, address, count, 0)
    }
    guard bytesRead == count else {
      throw CodexSessionIndexError.readFailed
    }
    return data
  }

  private func parse(_ data: Data) -> (
    entries: [CodexSessionIndexEntry], issues: [CodexSessionIndexIssue]
  ) {
    var entriesByID: [String: CodexSessionIndexEntry] = [:]
    var issues: [CodexSessionIndexIssue] = []
    let dateParser = CodexDateParser()

    for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
      guard rawLine.count <= Self.maximumRecordBytes else {
        issues.append(.invalidRecord)
        continue
      }
      guard
        let record = try? JSONDecoder().decode(SessionIndexRecord.self, from: Data(rawLine)),
        !record.id.isEmpty,
        !record.threadName.isEmpty,
        let updatedAt = dateParser.parse(record.updatedAt)
      else {
        issues.append(.invalidRecord)
        continue
      }
      let entry = CodexSessionIndexEntry(
        id: record.id.lowercased(),
        title: record.threadName,
        updatedAt: updatedAt
      )
      let normalizedID = record.id.lowercased()
      if entriesByID[normalizedID].map({ $0.updatedAt < updatedAt }) ?? true {
        entriesByID[normalizedID] = entry
      }
    }

    let entries = entriesByID.values.sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id < $1.id
    }
    return (entries, issues)
  }
}

private struct SessionIndexRecord: Decodable {
  let id: String
  let threadName: String
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case threadName = "thread_name"
    case updatedAt = "updated_at"
  }
}

struct CodexFileSignature: Equatable, Sendable {
  let device: UInt64
  let inode: UInt64
  let size: Int64
  let modifiedSeconds: Int64
  let modifiedNanoseconds: Int64

  init(status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
    size = Int64(status.st_size)
    modifiedSeconds = Int64(status.st_mtimespec.tv_sec)
    modifiedNanoseconds = Int64(status.st_mtimespec.tv_nsec)
  }
}
