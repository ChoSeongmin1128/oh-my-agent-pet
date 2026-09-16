import Darwin
import Foundation

public enum CodexSetupServiceError: Error, Equatable, Sendable {
  case executableMissing
  case codexUnavailable
  case unsafeHooksTarget
  case readFailed
  case writeFailed
  case backupFailed
  case concurrentModification
  case trustFailed
  case rollbackFailed
  case configuration(CodexHookConfigurationError)
}

public struct CodexSetupStatus: Codable, Equatable, Sendable {
  public let provider: String
  public let status: CodexHookInstallationState
  public let hooksPath: String

  enum CodingKeys: String, CodingKey {
    case provider
    case status
    case hooksPath = "hooks_path"
  }
}

public struct CodexSetupChange: Codable, Equatable, Sendable {
  public let provider: String
  public let action: String
  public let status: CodexHookInstallationState
  public let changed: Bool
  public let dryRun: Bool
  public let trustedHookCount: Int
  public let backupPath: String?

  enum CodingKeys: String, CodingKey {
    case provider
    case action
    case status
    case changed
    case dryRun = "dry_run"
    case trustedHookCount = "trusted_hook_count"
    case backupPath = "backup_path"
  }
}

public struct CodexSetupService: Sendable {
  public let hooksURL: URL
  public let executableURL: URL

  private let configuration = CodexHookConfiguration()
  private let trustManager: any CodexHookTrustManaging
  private let cwd: URL
  private let now: @Sendable () -> Date
  private let beforeWrite: @Sendable () -> Void

  public init(
    homeDirectory: URL,
    environment: [String: String],
    executableURL: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    let paths = CodexPaths(homeDirectory: homeDirectory, environment: environment)
    let resolvedExecutable = executableURL.resolvingSymlinksInPath().standardizedFileURL
    let hooksURL = paths.dataRoot.appendingPathComponent("hooks.json")
    let configuration = CodexHookConfiguration()
    var appServerEnvironment = environment
    appServerEnvironment["CODEX_HOME"] = paths.dataRoot.path
    self.init(
      hooksURL: hooksURL,
      executableURL: resolvedExecutable,
      cwd: homeDirectory,
      trustManager: CodexHookTrustManager(
        hooksURL: hooksURL,
        expectedCommand: configuration.command(executableURL: resolvedExecutable),
        environment: appServerEnvironment
      ),
      now: now,
      beforeWrite: {}
    )
  }

  init(
    hooksURL: URL,
    executableURL: URL,
    cwd: URL,
    trustManager: any CodexHookTrustManaging,
    now: @escaping @Sendable () -> Date,
    beforeWrite: @escaping @Sendable () -> Void
  ) {
    self.hooksURL = hooksURL
    self.executableURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
    self.cwd = cwd
    self.trustManager = trustManager
    self.now = now
    self.beforeWrite = beforeWrite
  }

  public func status() throws -> CodexSetupStatus {
    let data = try readHooks()
    let configured = try mapConfigurationError {
      try configuration.installationState(in: data, executableURL: executableURL)
    }
    let resolved: CodexHookInstallationState
    switch configured {
    case .notConfigured, .needsRepair:
      resolved = configured
    case .needsTrust:
      do {
        let inspection = try trustManager.inspect(cwd: cwd)
        if inspection.hookCount == CodexHookConfiguration.eventNames.count,
          inspection.trustedHookCount == inspection.hookCount
        {
          resolved = .connected
        } else if inspection.hookCount == CodexHookConfiguration.eventNames.count {
          resolved = .needsTrust
        } else {
          resolved = .needsRepair
        }
      } catch CodexHookTrustManager.Error.codexExecutableUnavailable {
        resolved = .codexUnavailable
      } catch {
        resolved = error is CodexHookTrustManager.Error ? .needsRepair : .codexUnavailable
      }
    case .connected, .codexUnavailable:
      resolved = configured
    }
    return CodexSetupStatus(provider: "codex", status: resolved, hooksPath: hooksURL.path)
  }

  public func connect(dryRun: Bool) throws -> CodexSetupChange {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw CodexSetupServiceError.executableMissing
    }
    let current = try readHooks()
    let installed = try mapConfigurationError {
      try configuration.installing(in: current, executableURL: executableURL)
    }
    let existingOwnedCount = try mapConfigurationError {
      try configuration.ownedHandlerCount(in: current)
    }
    let configChanged = current != installed
    if dryRun {
      return CodexSetupChange(
        provider: "codex",
        action: "connect",
        status: .connected,
        changed: configChanged,
        dryRun: true,
        trustedHookCount: CodexHookConfiguration.eventNames.count,
        backupPath: nil
      )
    }

    let replacedKeys: Set<String>
    if existingOwnedCount > 0 {
      do {
        replacedKeys = try trustManager.keysForRemoval(cwd: cwd)
      } catch CodexHookTrustManager.Error.codexExecutableUnavailable {
        throw CodexSetupServiceError.codexUnavailable
      } catch {
        throw CodexSetupServiceError.trustFailed
      }
    } else {
      replacedKeys = []
    }

    let mutation = try apply(installed, replacing: current, removeIfEmpty: false)
    do {
      let trust = try trustManager.activate(
        cwd: cwd,
        expectedHookCount: CodexHookConfiguration.eventNames.count,
        replacing: replacedKeys
      )
      return CodexSetupChange(
        provider: "codex",
        action: "connect",
        status: .connected,
        changed: configChanged || trust.changed,
        dryRun: false,
        trustedHookCount: trust.trustedHookCount,
        backupPath: mutation?.backupURL?.path
      )
    } catch CodexHookTrustManager.Error.codexExecutableUnavailable {
      try rollbackIfNeeded(mutation, original: current)
      throw CodexSetupServiceError.codexUnavailable
    } catch CodexHookTrustManager.Error.rollbackFailed {
      try rollbackIfNeeded(mutation, original: current)
      throw CodexSetupServiceError.rollbackFailed
    } catch {
      try rollbackIfNeeded(mutation, original: current)
      throw CodexSetupServiceError.trustFailed
    }
  }

  public func disconnect(dryRun: Bool) throws -> CodexSetupChange {
    let current = try readHooks()
    let removed = try mapConfigurationError { try configuration.removing(from: current) }
    let configChanged = current != removed
    if dryRun || !configChanged {
      return CodexSetupChange(
        provider: "codex",
        action: "disconnect",
        status: .notConfigured,
        changed: configChanged,
        dryRun: dryRun,
        trustedHookCount: 0,
        backupPath: nil
      )
    }

    let trustedKeys: Set<String>
    do {
      trustedKeys = try trustManager.keysForRemoval(cwd: cwd)
    } catch CodexHookTrustManager.Error.codexExecutableUnavailable {
      throw CodexSetupServiceError.codexUnavailable
    } catch {
      throw CodexSetupServiceError.trustFailed
    }

    let mutation = try apply(removed, replacing: current, removeIfEmpty: true)
    do {
      _ = try trustManager.removeTrustedHookKeys(trustedKeys)
      return CodexSetupChange(
        provider: "codex",
        action: "disconnect",
        status: .notConfigured,
        changed: true,
        dryRun: false,
        trustedHookCount: 0,
        backupPath: mutation?.backupURL?.path
      )
    } catch CodexHookTrustManager.Error.rollbackFailed {
      try rollbackIfNeeded(mutation, original: current)
      throw CodexSetupServiceError.rollbackFailed
    } catch {
      try rollbackIfNeeded(mutation, original: current)
      throw CodexSetupServiceError.trustFailed
    }
  }

  private func readHooks() throws -> Data {
    guard !isSymbolicLink(hooksURL) else {
      throw CodexSetupServiceError.unsafeHooksTarget
    }
    guard FileManager.default.fileExists(atPath: hooksURL.path) else {
      return Data("{}".utf8)
    }
    do {
      return try Data(contentsOf: hooksURL)
    } catch {
      throw CodexSetupServiceError.readFailed
    }
  }

  private func apply(
    _ updated: Data,
    replacing current: Data,
    removeIfEmpty: Bool
  ) throws -> CodexFileMutation? {
    guard updated != current else { return nil }
    beforeWrite()
    guard try readHooks() == current else {
      throw CodexSetupServiceError.concurrentModification
    }

    let fileManager = FileManager.default
    let existed = fileManager.fileExists(atPath: hooksURL.path)
    do {
      try fileManager.createDirectory(
        at: hooksURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
      )
    } catch {
      throw CodexSetupServiceError.writeFailed
    }

    let backup: URL?
    if existed {
      backup = backupURL()
      do {
        try fileManager.copyItem(at: hooksURL, to: backup!)
      } catch {
        throw CodexSetupServiceError.backupFailed
      }
    } else {
      backup = nil
    }

    do {
      if removeIfEmpty, try isEmptyRoot(updated) {
        try fileManager.removeItem(at: hooksURL)
      } else {
        try SecureCodexFile.write(
          updated,
          to: hooksURL,
          permissions: currentPermissions() ?? 0o600
        )
      }
    } catch {
      throw CodexSetupServiceError.writeFailed
    }
    return CodexFileMutation(backupURL: backup, originalExisted: existed)
  }

  private func isEmptyRoot(_ data: Data) throws -> Bool {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return false
    }
    return root.isEmpty
  }

  private func rollbackIfNeeded(_ mutation: CodexFileMutation?, original: Data) throws {
    guard let mutation else { return }
    do {
      if mutation.originalExisted {
        try SecureCodexFile.write(
          original,
          to: hooksURL,
          permissions: currentPermissions() ?? 0o600
        )
      } else if FileManager.default.fileExists(atPath: hooksURL.path) {
        try FileManager.default.removeItem(at: hooksURL)
      }
    } catch {
      throw CodexSetupServiceError.rollbackFailed
    }
  }

  private func backupURL() -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    let baseName = "hooks.json.omapet-backup-\(formatter.string(from: now()))"
    let directory = hooksURL.deletingLastPathComponent()
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
      hooksURL.withUnsafeFileSystemRepresentation({ path in
        guard let path else { return -1 }
        return lstat(path, &fileStatus)
      }) == 0
    else { return nil }
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
    } catch let error as CodexHookConfigurationError {
      throw CodexSetupServiceError.configuration(error)
    }
  }
}

private struct CodexFileMutation {
  let backupURL: URL?
  let originalExisted: Bool
}

private enum SecureCodexFile {
  static func write(_ data: Data, to url: URL, permissions: mode_t) throws {
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).omapet-\(UUID().uuidString).tmp"
    )
    let descriptor = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
    }
    guard descriptor >= 0 else { throw CodexSetupServiceError.writeFailed }

    var writeSucceeded = false
    defer {
      Darwin.close(descriptor)
      if !writeSucceeded { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var written = 0
      while written < bytes.count {
        let count = Darwin.write(
          descriptor,
          baseAddress.advanced(by: written),
          bytes.count - written
        )
        if count > 0 {
          written += count
        } else if count == -1, errno == EINTR {
          continue
        } else {
          throw CodexSetupServiceError.writeFailed
        }
      }
    }
    guard fchmod(descriptor, permissions) == 0, fsync(descriptor) == 0 else {
      throw CodexSetupServiceError.writeFailed
    }

    let renamed = temporaryURL.withUnsafeFileSystemRepresentation { sourcePath in
      url.withUnsafeFileSystemRepresentation { destinationPath in
        guard let sourcePath, let destinationPath else { return Int32(-1) }
        return Darwin.rename(sourcePath, destinationPath)
      }
    }
    guard renamed == 0 else { throw CodexSetupServiceError.writeFailed }
    writeSucceeded = true
  }
}
