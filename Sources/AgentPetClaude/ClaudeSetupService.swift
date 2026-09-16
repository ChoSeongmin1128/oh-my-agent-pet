import Darwin
import Foundation

public enum ClaudeSetupServiceError: Error, Equatable, Sendable {
  case executableMissing
  case unsafeSettingsTarget
  case readFailed
  case writeFailed
  case backupFailed
  case concurrentModification
  case configuration(ClaudeHookConfigurationError)
}

public struct ClaudeSetupStatus: Codable, Equatable, Sendable {
  public let provider: String
  public let status: ClaudeHookInstallationState
  public let settingsPath: String

  enum CodingKeys: String, CodingKey {
    case provider
    case status
    case settingsPath = "settings_path"
  }
}

public struct ClaudeSetupChange: Codable, Equatable, Sendable {
  public let provider: String
  public let action: String
  public let status: ClaudeHookInstallationState
  public let changed: Bool
  public let dryRun: Bool
  public let backupPath: String?

  enum CodingKeys: String, CodingKey {
    case provider
    case action
    case status
    case changed
    case dryRun = "dry_run"
    case backupPath = "backup_path"
  }
}

public struct ClaudeSetupService: Sendable {
  public let settingsURL: URL
  public let executableURL: URL

  private let configuration = ClaudeHookConfiguration()
  private let now: @Sendable () -> Date
  private let beforeWrite: @Sendable () -> Void

  public init(
    homeDirectory: URL,
    environment: [String: String],
    executableURL: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.init(
      homeDirectory: homeDirectory,
      environment: environment,
      executableURL: executableURL,
      now: now,
      beforeWrite: {}
    )
  }

  init(
    homeDirectory: URL,
    environment: [String: String],
    executableURL: URL,
    now: @escaping @Sendable () -> Date,
    beforeWrite: @escaping @Sendable () -> Void
  ) {
    settingsURL =
      ClaudePaths(
        homeDirectory: homeDirectory,
        environment: environment
      ).settingsURL
    self.executableURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
    self.now = now
    self.beforeWrite = beforeWrite
  }

  public func status() throws -> ClaudeSetupStatus {
    let data = try readSettings()
    return ClaudeSetupStatus(
      provider: "claude",
      status: try mapConfigurationError {
        try configuration.installationState(in: data, executableURL: executableURL)
      },
      settingsPath: settingsURL.path
    )
  }

  public func connect(dryRun: Bool) throws -> ClaudeSetupChange {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw ClaudeSetupServiceError.executableMissing
    }
    let current = try readSettings()
    let installed = try mapConfigurationError {
      try configuration.installing(in: current, executableURL: executableURL)
    }
    let status = try mapConfigurationError {
      try configuration.installationState(in: installed, executableURL: executableURL)
    }
    let changed = current != installed
    let backup = try apply(installed, replacing: current, dryRun: dryRun)
    return ClaudeSetupChange(
      provider: "claude",
      action: "connect",
      status: status,
      changed: changed,
      dryRun: dryRun,
      backupPath: backup?.path
    )
  }

  public func disconnect(dryRun: Bool) throws -> ClaudeSetupChange {
    let current = try readSettings()
    let removed = try mapConfigurationError {
      try configuration.removing(from: current)
    }
    let changed = current != removed
    let backup = try apply(removed, replacing: current, dryRun: dryRun)
    return ClaudeSetupChange(
      provider: "claude",
      action: "disconnect",
      status: .notConfigured,
      changed: changed,
      dryRun: dryRun,
      backupPath: backup?.path
    )
  }

  private func readSettings() throws -> Data {
    guard !isSymbolicLink(settingsURL) else {
      throw ClaudeSetupServiceError.unsafeSettingsTarget
    }
    guard FileManager.default.fileExists(atPath: settingsURL.path) else {
      return Data("{}".utf8)
    }
    do {
      return try Data(contentsOf: settingsURL)
    } catch {
      throw ClaudeSetupServiceError.readFailed
    }
  }

  private func apply(_ updated: Data, replacing current: Data, dryRun: Bool) throws -> URL? {
    guard updated != current, !dryRun else {
      return nil
    }

    beforeWrite()
    guard try readSettings() == current else {
      throw ClaudeSetupServiceError.concurrentModification
    }

    let fileManager = FileManager.default
    let existed = fileManager.fileExists(atPath: settingsURL.path)
    do {
      try fileManager.createDirectory(
        at: settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
      )
    } catch {
      throw ClaudeSetupServiceError.writeFailed
    }

    let backup: URL?
    if existed {
      backup = backupURL()
      do {
        try fileManager.copyItem(at: settingsURL, to: backup!)
      } catch {
        throw ClaudeSetupServiceError.backupFailed
      }
    } else {
      backup = nil
    }

    do {
      try SecureAtomicFile.write(
        updated, to: settingsURL, permissions: currentPermissions() ?? 0o600)
    } catch {
      throw ClaudeSetupServiceError.writeFailed
    }
    return backup
  }

  private func backupURL() -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    let baseName = "settings.json.omapet-backup-\(formatter.string(from: now()))"
    let directory = settingsURL.deletingLastPathComponent()
    var candidate = directory.appendingPathComponent(baseName)
    var suffix = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)-\(suffix)")
      suffix += 1
    }
    return candidate
  }

  private func currentPermissions() -> mode_t? {
    var fileStatus = stat()
    guard
      settingsURL.withUnsafeFileSystemRepresentation({ path in
        guard let path else { return -1 }
        return lstat(path, &fileStatus)
      }) == 0
    else {
      return nil
    }
    return fileStatus.st_mode & 0o777
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    var fileStatus = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &fileStatus)
    }
    return result == 0 && fileStatus.st_mode & S_IFMT == S_IFLNK
  }

  private func mapConfigurationError<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as ClaudeHookConfigurationError {
      throw ClaudeSetupServiceError.configuration(error)
    }
  }

}

private enum SecureAtomicFile {
  static func write(_ data: Data, to url: URL, permissions: mode_t) throws {
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).omapet-\(UUID().uuidString).tmp"
    )
    let descriptor = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
    }
    guard descriptor >= 0 else {
      throw ClaudeSetupServiceError.writeFailed
    }

    var writeSucceeded = false
    defer {
      Darwin.close(descriptor)
      if !writeSucceeded {
        try? FileManager.default.removeItem(at: temporaryURL)
      }
    }

    let written = data.withUnsafeBytes { bytes -> Int in
      guard let address = bytes.baseAddress else { return 0 }
      return Darwin.write(descriptor, address, bytes.count)
    }
    guard written == data.count,
      fchmod(descriptor, permissions) == 0,
      fsync(descriptor) == 0
    else {
      throw ClaudeSetupServiceError.writeFailed
    }

    let renameResult = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
      url.withUnsafeFileSystemRepresentation { destinationPath in
        guard let temporaryPath, let destinationPath else { return Int32(-1) }
        return Darwin.rename(temporaryPath, destinationPath)
      }
    }
    guard renameResult == 0 else {
      throw ClaudeSetupServiceError.writeFailed
    }
    writeSucceeded = true
  }
}
