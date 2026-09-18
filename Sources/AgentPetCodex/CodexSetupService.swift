import AgentPetCore
import AgentPetInfrastructure
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
  private let fileStore: SecureConfigurationFileStore
  private let trustManager: any CodexHookTrustManaging
  private let cwd: URL
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
    fileStore = SecureConfigurationFileStore(url: hooksURL, now: now)
    self.trustManager = trustManager
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
    return CodexSetupStatus(
      provider: ProviderIdentifier.codex.rawValue,
      status: resolved,
      hooksPath: hooksURL.path
    )
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
        provider: ProviderIdentifier.codex.rawValue,
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
        provider: ProviderIdentifier.codex.rawValue,
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
        provider: ProviderIdentifier.codex.rawValue,
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
        provider: ProviderIdentifier.codex.rawValue,
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
    do {
      return try fileStore.read(defaultData: Data("{}".utf8))
    } catch let error as SecureConfigurationFileError {
      throw mapFileError(error)
    }
  }

  private func apply(
    _ updated: Data,
    replacing current: Data,
    removeIfEmpty: Bool
  ) throws -> SecureConfigurationMutation? {
    guard updated != current else { return nil }
    beforeWrite()
    do {
      return try fileStore.replace(
        with: updated,
        expected: current,
        defaultData: Data("{}".utf8),
        removeInsteadOfWrite: removeIfEmpty && isEmptyRoot(updated)
      )
    } catch let error as SecureConfigurationFileError {
      throw mapFileError(error)
    }
  }

  private func isEmptyRoot(_ data: Data) throws -> Bool {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return false
    }
    return root.isEmpty
  }

  private func rollbackIfNeeded(_ mutation: SecureConfigurationMutation?, original: Data) throws {
    do {
      try fileStore.rollback(mutation, original: original)
    } catch let error as SecureConfigurationFileError {
      _ = error
      throw CodexSetupServiceError.rollbackFailed
    }
  }

  private func mapConfigurationError<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as CodexHookConfigurationError {
      throw CodexSetupServiceError.configuration(error)
    }
  }

  private func mapFileError(_ error: SecureConfigurationFileError) -> CodexSetupServiceError {
    switch error {
    case .unsafeTarget: .unsafeHooksTarget
    case .readFailed: .readFailed
    case .writeFailed: .writeFailed
    case .backupFailed: .backupFailed
    case .concurrentModification: .concurrentModification
    }
  }
}
