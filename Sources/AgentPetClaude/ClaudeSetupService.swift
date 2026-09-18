import AgentPetCore
import AgentPetInfrastructure
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
  private let fileStore: SecureConfigurationFileStore
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
    fileStore = SecureConfigurationFileStore(url: settingsURL, now: now)
    self.beforeWrite = beforeWrite
  }

  public func status() throws -> ClaudeSetupStatus {
    let data = try readSettings()
    return ClaudeSetupStatus(
      provider: ProviderIdentifier.claude.rawValue,
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
      provider: ProviderIdentifier.claude.rawValue,
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
      provider: ProviderIdentifier.claude.rawValue,
      action: "disconnect",
      status: .notConfigured,
      changed: changed,
      dryRun: dryRun,
      backupPath: backup?.path
    )
  }

  private func readSettings() throws -> Data {
    do {
      return try fileStore.read(defaultData: Data("{}".utf8))
    } catch let error as SecureConfigurationFileError {
      throw mapFileError(error)
    }
  }

  private func apply(_ updated: Data, replacing current: Data, dryRun: Bool) throws -> URL? {
    guard updated != current, !dryRun else {
      return nil
    }

    beforeWrite()
    do {
      return try fileStore.replace(
        with: updated,
        expected: current,
        defaultData: Data("{}".utf8)
      )
      .flatMap(\.backupURL)
    } catch let error as SecureConfigurationFileError {
      throw mapFileError(error)
    }
  }

  private func mapConfigurationError<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as ClaudeHookConfigurationError {
      throw ClaudeSetupServiceError.configuration(error)
    }
  }

  private func mapFileError(_ error: SecureConfigurationFileError) -> ClaudeSetupServiceError {
    switch error {
    case .unsafeTarget: .unsafeSettingsTarget
    case .readFailed: .readFailed
    case .writeFailed: .writeFailed
    case .backupFailed: .backupFailed
    case .concurrentModification: .concurrentModification
    }
  }
}
