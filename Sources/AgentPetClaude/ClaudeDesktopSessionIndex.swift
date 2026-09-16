import Darwin
import Foundation

struct ClaudeDesktopSessionIndex: Sendable {
  static let maximumFileCount = 4_096
  static let maximumFileBytes = 512 * 1_024
  static let maximumTotalReadBytes = 64 * 1_024 * 1_024

  let sessionsDirectory: URL
  private var cache: [URL: CachedDesktopRoute] = [:]

  init(sessionsDirectory: URL) {
    self.sessionsDirectory = sessionsDirectory
  }

  mutating func routes() -> [String: String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: sessionsDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      cache.removeAll(keepingCapacity: true)
      return [:]
    }

    var nextCache: [URL: CachedDesktopRoute] = [:]
    var visited = 0
    var uncachedBytesRead = 0
    while let url = enumerator.nextObject() as? URL {
      visited += 1
      guard visited <= Self.maximumFileCount else { break }
      guard url.pathExtension == "json",
        let record = readRecord(
          at: url,
          maximumBytesToRead: Self.maximumTotalReadBytes - uncachedBytesRead
        )
      else { continue }
      uncachedBytesRead += record.data.count
      if let cached = cache[url], cached.signature == record.signature {
        nextCache[url] = cached
      } else if let metadata = decode(record.data) {
        nextCache[url] = CachedDesktopRoute(signature: record.signature, metadata: metadata)
      }
    }
    cache = nextCache

    var routes: [String: DesktopRouteMetadata] = [:]
    for cached in cache.values where !cached.metadata.isArchived {
      let metadata = cached.metadata
      if let existing = routes[metadata.cliSessionID],
        existing.lastActivityAt > metadata.lastActivityAt
      {
        continue
      }
      routes[metadata.cliSessionID] = metadata
    }
    return routes.mapValues(\.desktopSessionID)
  }

  private func readRecord(
    at url: URL,
    maximumBytesToRead: Int
  ) -> (signature: DesktopFileSignature, data: Data)? {
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return nil }
    defer { Darwin.close(descriptor) }

    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_size > 0,
      status.st_size <= Self.maximumFileBytes
    else { return nil }
    let signature = DesktopFileSignature(status: status)
    if let cached = cache[url], cached.signature == signature {
      return (signature, Data())
    }
    guard status.st_size <= maximumBytesToRead else { return nil }
    var data = Data(count: Int(status.st_size))
    let count = data.withUnsafeMutableBytes { bytes in
      Darwin.pread(descriptor, bytes.baseAddress, bytes.count, 0)
    }
    guard count == data.count else { return nil }
    return (signature, data)
  }

  private func decode(_ data: Data) -> DesktopRouteMetadata? {
    guard !data.isEmpty,
      let raw = try? JSONDecoder().decode(DesktopSessionMetadata.self, from: data),
      let cliSessionID = boundedIdentifier(raw.cliSessionID, maximum: 512),
      let desktopSessionID = validatedDesktopSessionID(raw.sessionID)
    else { return nil }
    return DesktopRouteMetadata(
      cliSessionID: cliSessionID,
      desktopSessionID: desktopSessionID,
      lastActivityAt: raw.lastActivityAt ?? 0,
      isArchived: raw.isArchived == true
    )
  }

  private func boundedIdentifier(_ value: String, maximum: Int) -> String? {
    guard !value.isEmpty, value.utf8.count <= maximum,
      value.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:")).contains($0)
      })
    else { return nil }
    return value
  }

  private func validatedDesktopSessionID(_ value: String) -> String? {
    guard value.hasPrefix("local_"),
      UUID(uuidString: String(value.dropFirst(6))) != nil
    else { return nil }
    return value
  }
}

private struct DesktopSessionMetadata: Decodable {
  let sessionID: String
  let cliSessionID: String
  let isArchived: Bool?
  let lastActivityAt: Double?

  enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case cliSessionID = "cliSessionId"
    case isArchived
    case lastActivityAt
  }
}

private struct DesktopRouteMetadata: Sendable {
  let cliSessionID: String
  let desktopSessionID: String
  let lastActivityAt: Double
  let isArchived: Bool
}

private struct CachedDesktopRoute: Sendable {
  let signature: DesktopFileSignature
  let metadata: DesktopRouteMetadata
}

private struct DesktopFileSignature: Equatable, Sendable {
  let device: UInt64
  let inode: UInt64
  let size: Int64
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int

  init(status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
    size = status.st_size
    modifiedSeconds = status.st_mtimespec.tv_sec
    modifiedNanoseconds = status.st_mtimespec.tv_nsec
  }
}
