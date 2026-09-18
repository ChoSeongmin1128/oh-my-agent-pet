import AgentPetClaude
import AgentPetCodex
import AgentPetCore
import AgentPetEvents
import AgentPetLibrary
import Foundation

public struct OmapetCommandResult: Equatable, Sendable {
  public let exitCode: Int32
  public let standardOutput: String
  public let standardError: String

  public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

public struct OmapetCommandRunner: Sendable {
  public static let version = AgentPetProduct.developmentVersion
  public static let maximumHookInputBytes = AgentHookRecorder.maximumInputBytes

  private let claudeSetupService: ClaudeSetupService
  private let codexSetupService: CodexSetupService
  private let claudeHookRecorder: AgentHookRecorder
  private let codexHookRecorder: AgentHookRecorder
  private let petCommands: OmapetPetCommands

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL? = nil,
    executableURL: URL? = nil,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    petPackageDownloader: PetPackageDownloader = URLSessionPetPackageDownloader(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    let resolvedHome =
      homeDirectory
      ?? environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    let resolvedExecutable =
      executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "omapet")
    let paths = ClaudePaths(homeDirectory: resolvedHome, environment: environment)
    claudeSetupService = ClaudeSetupService(
      homeDirectory: resolvedHome,
      environment: environment,
      executableURL: resolvedExecutable,
      now: now
    )
    codexSetupService = CodexSetupService(
      homeDirectory: resolvedHome,
      environment: environment,
      executableURL: resolvedExecutable,
      now: now
    )
    claudeHookRecorder = AgentHookRecorder(
      provider: .claude,
      applicationSupportDirectory: paths.applicationSupportDirectory
    )
    codexHookRecorder = AgentHookRecorder(
      provider: .codex,
      applicationSupportDirectory: paths.applicationSupportDirectory
    )
    petCommands = OmapetPetCommands(
      service: PetLibraryService(
        paths: PetLibraryPaths(applicationSupportDirectory: paths.applicationSupportDirectory),
        downloader: petPackageDownloader,
        now: now
      ),
      currentDirectory: currentDirectory
    )
  }

  public func run(arguments: [String], standardInput: Data = Data()) -> OmapetCommandResult {
    do {
      return execute(
        try OmapetCommandParser.parse(arguments: arguments), standardInput: standardInput)
    } catch {
      return OmapetCommandResult(
        exitCode: 64,
        standardError: "\(error)\n\n\(Self.helpText)"
      )
    }
  }

  private func execute(_ command: OmapetCommand, standardInput: Data) -> OmapetCommandResult {
    switch command {
    case .help:
      return OmapetCommandResult(exitCode: 0, standardOutput: Self.helpText)
    case .version(let json):
      if json {
        return jsonResult(VersionOutput(name: AgentPetProduct.name, version: Self.version))
      }
      return OmapetCommandResult(
        exitCode: 0,
        standardOutput: "\(AgentPetProduct.name) \(Self.version)\n"
      )
    case .doctor(let json):
      let output = OmapetDoctor(
        claudeSetupService: claudeSetupService,
        codexSetupService: codexSetupService,
        petService: petCommands.service,
        eventsURL: claudeHookRecorder.eventsURL
      ).inspect(version: Self.version)
      if json {
        return jsonResult(output, exitCode: output.status == "fail" ? 74 : 0)
      }
      let lines = output.checks.map {
        "\($0.id): \($0.status)" + ($0.detail.map { " (\($0))" } ?? "")
      }
      return OmapetCommandResult(
        exitCode: output.status == "fail" ? 74 : 0,
        standardOutput:
          "Status: \(output.status)\nVersion: \(Self.version)\n"
          + lines.joined(separator: "\n") + "\n"
      )
    case .setupStatus(let json):
      do {
        let status = try claudeSetupService.status()
        if json {
          return jsonResult(status)
        }
        return OmapetCommandResult(
          exitCode: 0,
          standardOutput: "Claude: \(status.status.rawValue)\n"
        )
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupStatusCodex(let json):
      do {
        let status = try codexSetupService.status()
        if json { return jsonResult(status) }
        return OmapetCommandResult(
          exitCode: 0,
          standardOutput: "Codex: \(status.status.rawValue)\n"
        )
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupConnectClaude(let json, let dryRun):
      do {
        let change = try claudeSetupService.connect(dryRun: dryRun)
        return setupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupDisconnectClaude(let json, let dryRun):
      do {
        let change = try claudeSetupService.disconnect(dryRun: dryRun)
        return setupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupConnectCodex(let json, let dryRun):
      do {
        let change = try codexSetupService.connect(dryRun: dryRun)
        return codexSetupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupDisconnectCodex(let json, let dryRun):
      do {
        let change = try codexSetupService.disconnect(dryRun: dryRun)
        return codexSetupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .hookClaude:
      _ = try? claudeHookRecorder.record(input: standardInput)
      return OmapetCommandResult(exitCode: 0)
    case .hookCodex:
      _ = try? codexHookRecorder.record(input: standardInput)
      return OmapetCommandResult(exitCode: 0)
    case .petList(let json):
      return petCommands.list(json: json)
    case .petInspect(let source, let json):
      return petCommands.inspect(source: source, json: json, dryRun: nil)
    case .petInstall(let source, let json, let dryRun):
      if dryRun {
        return petCommands.inspect(source: source, json: json, dryRun: true)
      }
      return petCommands.install(source: source, json: json)
    case .petSelect(let identifier, let json):
      return petCommands.select(identifier: identifier, json: json)
    case .petRemove(let recordID, let json):
      return petCommands.remove(recordID: recordID, json: json)
    }
  }

  private func setupChangeResult(_ change: ClaudeSetupChange, json: Bool) -> OmapetCommandResult {
    if json {
      return jsonResult(change)
    }
    let mode = change.dryRun ? "dry-run" : (change.changed ? "changed" : "unchanged")
    var output = "Claude: \(change.status.rawValue) (\(mode))\n"
    if let backupPath = change.backupPath {
      output += "Backup: \(backupPath)\n"
    }
    return OmapetCommandResult(exitCode: 0, standardOutput: output)
  }

  private func codexSetupChangeResult(
    _ change: CodexSetupChange,
    json: Bool
  ) -> OmapetCommandResult {
    if json { return jsonResult(change) }
    let mode = change.dryRun ? "dry-run" : (change.changed ? "changed" : "unchanged")
    var output = "Codex: \(change.status.rawValue) (\(mode))\n"
    if let backupPath = change.backupPath { output += "Backup: \(backupPath)\n" }
    return OmapetCommandResult(exitCode: 0, standardOutput: output)
  }

  private func setupErrorResult(_ error: Error, json: Bool) -> OmapetCommandResult {
    let mapped = SetupErrorOutput(error: error)
    if json {
      return jsonResult(mapped, exitCode: mapped.exitCode)
    }
    return OmapetCommandResult(
      exitCode: mapped.exitCode,
      standardError: "Setup failed: \(mapped.code)\n"
    )
  }

  private func jsonResult(_ value: some Encodable, exitCode: Int32 = 0) -> OmapetCommandResult {
    OmapetJSON.result(value, exitCode: exitCode)
  }

  private static let helpText = """
    Usage:
      omapet version [--json]
      omapet doctor [--json]
      omapet setup status [--json]
      omapet setup status codex [--json]
      omapet setup connect claude [--dry-run] [--json]
      omapet setup disconnect claude [--dry-run] [--json]
      omapet setup connect codex [--dry-run] [--json]
      omapet setup disconnect codex [--dry-run] [--json]
      omapet pet list [--json]
      omapet pet inspect <package-folder|codex-pet.zip|codex-pets.net-url> [--json]
      omapet pet install <package-folder|codex-pet.zip|codex-pets.net-url> [--dry-run] [--json]
      omapet pet select <original|none|pet-id> [--json]
      omapet pet remove <pet-id> [--json]

    """
}

private struct VersionOutput: Encodable {
  let name: String
  let version: String
}

private struct SetupErrorOutput: Encodable {
  let status = "error"
  let code: String
  let exitCode: Int32

  enum CodingKeys: String, CodingKey {
    case status
    case code
  }

  init(error: Error) {
    switch error {
    case ClaudeSetupServiceError.executableMissing,
      CodexSetupServiceError.executableMissing:
      code = "executable_missing"
      exitCode = 69
    case CodexSetupServiceError.codexUnavailable:
      code = "codex_unavailable"
      exitCode = 69
    case ClaudeSetupServiceError.unsafeSettingsTarget,
      CodexSetupServiceError.unsafeHooksTarget:
      code = "unsafe_settings_target"
      exitCode = 73
    case ClaudeSetupServiceError.configuration,
      CodexSetupServiceError.configuration:
      code = "invalid_configuration"
      exitCode = 65
    case ClaudeSetupServiceError.readFailed,
      CodexSetupServiceError.readFailed:
      code = "settings_read_failed"
      exitCode = 74
    case ClaudeSetupServiceError.backupFailed,
      CodexSetupServiceError.backupFailed:
      code = "settings_backup_failed"
      exitCode = 74
    case ClaudeSetupServiceError.concurrentModification,
      CodexSetupServiceError.concurrentModification:
      code = "settings_changed"
      exitCode = 75
    case CodexSetupServiceError.trustFailed:
      code = "codex_trust_failed"
      exitCode = 74
    case CodexSetupServiceError.rollbackFailed:
      code = "rollback_failed"
      exitCode = 74
    default:
      code = "settings_write_failed"
      exitCode = 74
    }
  }
}
