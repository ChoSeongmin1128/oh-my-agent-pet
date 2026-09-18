import Darwin
import Foundation

public enum SecureConfigurationFileError: Error, Equatable, Sendable {
  case unsafeTarget
  case readFailed
  case writeFailed
  case backupFailed
  case concurrentModification
}

public struct SecureConfigurationMutation: Equatable, Sendable {
  public let backupURL: URL?
  public let originalExisted: Bool
  public let originalPermissions: UInt16

  public init(backupURL: URL?, originalExisted: Bool, originalPermissions: UInt16) {
    self.backupURL = backupURL
    self.originalExisted = originalExisted
    self.originalPermissions = originalPermissions
  }
}

public struct SecureConfigurationFileStore: Sendable {
  public let url: URL
  private let now: @Sendable () -> Date

  public init(
    url: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.url = url.standardizedFileURL
    self.now = now
  }

  public func read(defaultData: Data = Data()) throws -> Data {
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT { return defaultData }
      if errno == ELOOP { throw SecureConfigurationFileError.unsafeTarget }
      throw SecureConfigurationFileError.readFailed
    }
    defer { Darwin.close(descriptor) }

    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_size >= 0
    else {
      throw SecureConfigurationFileError.unsafeTarget
    }

    var data = Data()
    data.reserveCapacity(Int(status.st_size))
    var offset: off_t = 0
    while offset < status.st_size {
      let requested = min(64 * 1_024, Int(status.st_size - offset))
      var buffer = [UInt8](repeating: 0, count: requested)
      let count = pread(descriptor, &buffer, requested, offset)
      if count < 0 {
        if errno == EINTR { continue }
        throw SecureConfigurationFileError.readFailed
      }
      guard count > 0 else { throw SecureConfigurationFileError.readFailed }
      data.append(contentsOf: buffer.prefix(count))
      offset += off_t(count)
    }
    return data
  }

  public func replace(
    with updated: Data,
    expected current: Data,
    defaultData: Data = Data(),
    removeInsteadOfWrite: Bool = false
  ) throws -> SecureConfigurationMutation? {
    guard updated != current else { return nil }
    guard try read(defaultData: defaultData) == current else {
      throw SecureConfigurationFileError.concurrentModification
    }

    let existed = itemType(at: url) == .regular
    let permissions = currentPermissions() ?? 0o600
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
      )
    } catch {
      throw SecureConfigurationFileError.writeFailed
    }

    let backup: URL?
    if existed {
      let destination = backupURL()
      do {
        try Self.atomicWrite(
          current,
          to: destination,
          permissions: mode_t(permissions)
        )
      } catch {
        throw SecureConfigurationFileError.backupFailed
      }
      backup = destination
    } else {
      backup = nil
    }

    do {
      if removeInsteadOfWrite {
        if existed {
          try FileManager.default.removeItem(at: url)
        }
      } else {
        try Self.atomicWrite(updated, to: url, permissions: mode_t(permissions))
      }
    } catch let error as SecureConfigurationFileError {
      throw error
    } catch {
      throw SecureConfigurationFileError.writeFailed
    }

    return SecureConfigurationMutation(
      backupURL: backup,
      originalExisted: existed,
      originalPermissions: permissions
    )
  }

  public func rollback(
    _ mutation: SecureConfigurationMutation?,
    original: Data
  ) throws {
    guard let mutation else { return }
    do {
      if mutation.originalExisted {
        try Self.atomicWrite(
          original,
          to: url,
          permissions: mode_t(mutation.originalPermissions)
        )
      } else if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } catch {
      throw SecureConfigurationFileError.writeFailed
    }
  }

  private enum ItemType {
    case missing
    case regular
    case unsafe
  }

  private func itemType(at url: URL) -> ItemType {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return lstat(path, &status)
    }
    if result != 0 {
      return errno == ENOENT ? .missing : .unsafe
    }
    return status.st_mode & S_IFMT == S_IFREG ? .regular : .unsafe
  }

  private func currentPermissions() -> UInt16? {
    var status = stat()
    guard
      url.withUnsafeFileSystemRepresentation({ path in
        guard let path else { return -1 }
        return lstat(path, &status)
      }) == 0,
      status.st_mode & S_IFMT == S_IFREG
    else {
      return nil
    }
    return UInt16(status.st_mode & 0o777)
  }

  private func backupURL() -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    let baseName = "\(url.lastPathComponent).omapet-backup-\(formatter.string(from: now()))"
    let directory = url.deletingLastPathComponent()
    var candidate = directory.appendingPathComponent(baseName)
    var suffix = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)-\(suffix)")
      suffix += 1
    }
    return candidate
  }

  private static func atomicWrite(_ data: Data, to url: URL, permissions: mode_t) throws {
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).omapet-\(UUID().uuidString).tmp"
    )
    let descriptor = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
    }
    guard descriptor >= 0 else {
      throw SecureConfigurationFileError.writeFailed
    }

    var writeSucceeded = false
    defer {
      Darwin.close(descriptor)
      if !writeSucceeded {
        try? FileManager.default.removeItem(at: temporaryURL)
      }
    }

    guard writeAll(data, to: descriptor),
      fchmod(descriptor, permissions) == 0,
      fsync(descriptor) == 0
    else {
      throw SecureConfigurationFileError.writeFailed
    }

    let renameResult = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
      url.withUnsafeFileSystemRepresentation { destinationPath in
        guard let temporaryPath, let destinationPath else { return Int32(-1) }
        return Darwin.rename(temporaryPath, destinationPath)
      }
    }
    guard renameResult == 0 else {
      throw SecureConfigurationFileError.writeFailed
    }
    writeSucceeded = true
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return data.isEmpty }
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if written > 0 {
          offset += written
          continue
        }
        if written < 0, errno == EINTR {
          continue
        }
        return false
      }
      return true
    }
  }
}
