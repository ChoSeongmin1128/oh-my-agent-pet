import Darwin
import Foundation

enum CodexRolloutCatalogError: Error, Equatable {
  case unsafeDirectory
  case listingFailed
}

struct CodexRolloutCandidate: Equatable {
  let sessionID: String
  let title: String?
  let indexUpdatedAt: Date
  let rolloutURL: URL
}

struct CodexRolloutCatalogResult {
  let candidates: [CodexRolloutCandidate]
  let watchDirectories: [URL]
}

struct CodexRolloutCatalog {
  let sessionsDirectory: URL
  let maximumSessions: Int

  func discover(indexEntries: [CodexSessionIndexEntry]) throws -> CodexRolloutCatalogResult {
    var watchDirectories: Set<URL> = [sessionsDirectory]
    let files = try rolloutFiles(watchDirectories: &watchDirectories)
    var candidates: [CodexRolloutCandidate] = []
    for entry in indexEntries {
      let suffix = "-\(entry.id).jsonl"
      guard
        let file =
          files
          .filter({ $0.url.lastPathComponent.hasSuffix(suffix) })
          .max(by: { $0.modifiedAt < $1.modifiedAt })
      else { continue }
      candidates.append(
        CodexRolloutCandidate(
          sessionID: entry.id,
          title: entry.title,
          indexUpdatedAt: entry.updatedAt,
          rolloutURL: file.url
        ))
      if candidates.count == maximumSessions { break }
    }

    if candidates.isEmpty {
      var bySessionID: [String: (url: URL, modifiedAt: Date)] = [:]
      for file in files {
        guard let sessionID = Self.rootSessionID(from: file.url) else { continue }
        if bySessionID[sessionID].map({ $0.modifiedAt < file.modifiedAt }) ?? true {
          bySessionID[sessionID] = file
        }
      }
      candidates = bySessionID.map { sessionID, file in
        CodexRolloutCandidate(
          sessionID: sessionID,
          title: nil,
          indexUpdatedAt: file.modifiedAt,
          rolloutURL: file.url
        )
      }
      .sorted {
        if $0.indexUpdatedAt != $1.indexUpdatedAt {
          return $0.indexUpdatedAt > $1.indexUpdatedAt
        }
        return $0.sessionID < $1.sessionID
      }
      .prefix(maximumSessions)
      .map { $0 }
    }

    return CodexRolloutCatalogResult(
      candidates: candidates,
      watchDirectories: watchDirectories.sorted { $0.path < $1.path }
    )
  }

  private func rolloutFiles(
    watchDirectories: inout Set<URL>
  ) throws -> [(url: URL, modifiedAt: Date)] {
    switch directoryState(sessionsDirectory) {
    case .missing:
      return []
    case .unsafe:
      throw CodexRolloutCatalogError.unsafeDirectory
    case .safe:
      break
    }

    var files: [(URL, Date)] = []
    for year in try directoryContents(sessionsDirectory)
    where matchesDigits(year.lastPathComponent, 4) {
      guard isSafeDirectory(year) else { continue }
      watchDirectories.insert(year)
      for month in try directoryContents(year) where matchesDigits(month.lastPathComponent, 2) {
        guard isSafeDirectory(month) else { continue }
        watchDirectories.insert(month)
        for day in try directoryContents(month) where matchesDigits(day.lastPathComponent, 2) {
          guard isSafeDirectory(day) else { continue }
          watchDirectories.insert(day)
          for file in try directoryContents(day) where file.lastPathComponent.hasPrefix("rollout-")
          {
            guard file.pathExtension == "jsonl", let modifiedAt = regularFileModificationDate(file)
            else { continue }
            files.append((file, modifiedAt))
          }
        }
      }
    }
    return files
  }

  private func directoryContents(_ directory: URL) throws -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    } catch {
      throw CodexRolloutCatalogError.listingFailed
    }
  }

  private func isSafeDirectory(_ url: URL) -> Bool {
    directoryState(url) == .safe
  }

  private func directoryState(_ url: URL) -> DirectoryState {
    var fileStatus = stat()
    let result = url.withUnsafeFileSystemRepresentation { filePath in
      guard let filePath else { return Int32(-1) }
      return lstat(filePath, &fileStatus)
    }
    if result != 0 {
      return errno == ENOENT ? .missing : .unsafe
    }
    return fileStatus.st_mode & S_IFMT == S_IFDIR ? .safe : .unsafe
  }

  private func regularFileModificationDate(_ url: URL) -> Date? {
    var fileStatus = stat()
    let result = url.withUnsafeFileSystemRepresentation { filePath in
      guard let filePath else { return Int32(-1) }
      return lstat(filePath, &fileStatus)
    }
    guard result == 0, fileStatus.st_mode & S_IFMT == S_IFREG else { return nil }
    return Date(
      timeIntervalSince1970: TimeInterval(fileStatus.st_mtimespec.tv_sec)
        + TimeInterval(fileStatus.st_mtimespec.tv_nsec) / 1_000_000_000
    )
  }

  private func matchesDigits(_ value: String, _ count: Int) -> Bool {
    value.count == count && value.allSatisfy(\.isNumber)
  }

  private static func rootSessionID(from url: URL) -> String? {
    let name = url.deletingPathExtension().lastPathComponent
    guard !name.contains("_"), name.count >= 36 else { return nil }
    let sessionID = String(name.suffix(36))
    return UUID(uuidString: sessionID) == nil ? nil : sessionID.lowercased()
  }
}

private enum DirectoryState {
  case safe
  case missing
  case unsafe
}
