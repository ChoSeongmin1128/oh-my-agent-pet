import AgentPetClaude
import Foundation

public enum OmapetCommand: Equatable, Sendable {
  case help
  case version(json: Bool)
  case doctor(json: Bool)
  case setupStatus(json: Bool)
  case setupConnectClaude(json: Bool, dryRun: Bool)
  case setupDisconnectClaude(json: Bool, dryRun: Bool)
  case hookClaude
}

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
  public static let version = "0.0.0-dev"
  public static let maximumHookInputBytes = ClaudeHookRecorder.maximumInputBytes

  private let setupService: ClaudeSetupService
  private let hookRecorder: ClaudeHookRecorder

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL? = nil,
    executableURL: URL? = nil,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    let resolvedHome =
      homeDirectory
      ?? environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    let resolvedExecutable =
      executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "omapet")
    setupService = ClaudeSetupService(
      homeDirectory: resolvedHome,
      environment: environment,
      executableURL: resolvedExecutable,
      now: now
    )
    hookRecorder = ClaudeHookRecorder(
      applicationSupportDirectory:
        resolvedHome
        .appendingPathComponent("Library/Application Support/Oh My Agent Pet", isDirectory: true)
    )
  }

  public func run(arguments: [String], standardInput: Data = Data()) -> OmapetCommandResult {
    do {
      return execute(try parse(arguments: arguments), standardInput: standardInput)
    } catch {
      return OmapetCommandResult(
        exitCode: 64,
        standardError: "\(error)\n\n\(Self.helpText)"
      )
    }
  }

  private func parse(arguments: [String]) throws -> OmapetCommand {
    if arguments == ["--help"] || arguments == ["-h"] {
      return .help
    }
    if arguments == ["--version"] {
      return .version(json: false)
    }

    let supportedOptions: Set<String> = ["--json", "--dry-run"]
    let unknownOptions = arguments.filter { $0.hasPrefix("-") && !supportedOptions.contains($0) }
    guard unknownOptions.isEmpty else {
      throw OmapetCLIError.unsupportedArguments(arguments)
    }

    let json = arguments.contains("--json")
    let dryRun = arguments.contains("--dry-run")
    let positional = arguments.filter { !supportedOptions.contains($0) }

    switch positional {
    case [] where !dryRun, ["help"] where !dryRun:
      return .help
    case ["version"] where !dryRun:
      return .version(json: json)
    case ["doctor"] where !dryRun:
      return .doctor(json: json)
    case ["setup", "status"] where !dryRun:
      return .setupStatus(json: json)
    case ["setup", "connect", "claude"]:
      return .setupConnectClaude(json: json, dryRun: dryRun)
    case ["setup", "disconnect", "claude"]:
      return .setupDisconnectClaude(json: json, dryRun: dryRun)
    case ["hook", "claude"] where !json && !dryRun:
      return .hookClaude
    default:
      throw OmapetCLIError.unsupportedArguments(positional)
    }
  }

  private func execute(_ command: OmapetCommand, standardInput: Data) -> OmapetCommandResult {
    switch command {
    case .help:
      return OmapetCommandResult(exitCode: 0, standardOutput: Self.helpText)
    case .version(let json):
      if json {
        return jsonResult(VersionOutput(name: "Oh My Agent Pet", version: Self.version))
      }
      return OmapetCommandResult(
        exitCode: 0,
        standardOutput: "Oh My Agent Pet \(Self.version)\n"
      )
    case .doctor(let json):
      let output = DoctorOutput(
        status: "pass",
        version: Self.version,
        checks: [DoctorCheck(id: "runtime", status: "pass")]
      )
      if json {
        return jsonResult(output)
      }
      return OmapetCommandResult(
        exitCode: 0,
        standardOutput: "Runtime: pass\nVersion: \(Self.version)\n"
      )
    case .setupStatus(let json):
      do {
        let status = try setupService.status()
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
    case .setupConnectClaude(let json, let dryRun):
      do {
        let change = try setupService.connect(dryRun: dryRun)
        return setupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .setupDisconnectClaude(let json, let dryRun):
      do {
        let change = try setupService.disconnect(dryRun: dryRun)
        return setupChangeResult(change, json: json)
      } catch {
        return setupErrorResult(error, json: json)
      }
    case .hookClaude:
      _ = try? hookRecorder.record(input: standardInput)
      return OmapetCommandResult(exitCode: 0)
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
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      let data = try encoder.encode(value)
      return OmapetCommandResult(
        exitCode: exitCode,
        standardOutput: String(decoding: data, as: UTF8.self) + "\n"
      )
    } catch {
      return OmapetCommandResult(
        exitCode: 70,
        standardError: "Failed to encode output.\n"
      )
    }
  }

  private static let helpText = """
    Usage:
      omapet version [--json]
      omapet doctor [--json]
      omapet setup status [--json]
      omapet setup connect claude [--dry-run] [--json]
      omapet setup disconnect claude [--dry-run] [--json]

    """
}

private enum OmapetCLIError: Error, CustomStringConvertible {
  case unsupportedArguments([String])

  var description: String {
    switch self {
    case .unsupportedArguments(let arguments):
      return "Unsupported arguments: \(arguments.joined(separator: " "))"
    }
  }
}

private struct VersionOutput: Encodable {
  let name: String
  let version: String
}

private struct DoctorOutput: Encodable {
  let status: String
  let version: String
  let checks: [DoctorCheck]
}

private struct DoctorCheck: Encodable {
  let id: String
  let status: String
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
    case ClaudeSetupServiceError.executableMissing:
      code = "executable_missing"
      exitCode = 69
    case ClaudeSetupServiceError.unsafeSettingsTarget:
      code = "unsafe_settings_target"
      exitCode = 73
    case ClaudeSetupServiceError.configuration:
      code = "invalid_configuration"
      exitCode = 65
    case ClaudeSetupServiceError.readFailed:
      code = "settings_read_failed"
      exitCode = 74
    case ClaudeSetupServiceError.backupFailed:
      code = "settings_backup_failed"
      exitCode = 74
    case ClaudeSetupServiceError.concurrentModification:
      code = "settings_changed"
      exitCode = 75
    default:
      code = "settings_write_failed"
      exitCode = 74
    }
  }
}
