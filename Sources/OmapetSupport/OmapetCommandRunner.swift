import Foundation

public enum OmapetCommand: Equatable, Sendable {
  case help
  case version(json: Bool)
  case doctor(json: Bool)
  case setupStatus(json: Bool)
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

  public init() {}

  public func run(arguments: [String]) -> OmapetCommandResult {
    do {
      return execute(try parse(arguments: arguments))
    } catch {
      return OmapetCommandResult(
        exitCode: 64,
        standardError: "\(error)\n\n\(Self.helpText)"
      )
    }
  }

  private func parse(arguments: [String]) throws -> OmapetCommand {
    let json = arguments.contains("--json")
    let positional = arguments.filter { $0 != "--json" }

    switch positional {
    case [], ["help"], ["--help"], ["-h"]:
      return .help
    case ["version"], ["--version"]:
      return .version(json: json)
    case ["doctor"]:
      return .doctor(json: json)
    case ["setup", "status"]:
      return .setupStatus(json: json)
    default:
      throw OmapetCLIError.unsupportedArguments(positional)
    }
  }

  private func execute(_ command: OmapetCommand) -> OmapetCommandResult {
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
      let output = SetupStatusOutput(status: "notConfigured", connections: [])
      if json {
        return jsonResult(output)
      }
      return OmapetCommandResult(
        exitCode: 0,
        standardOutput: "Setup: not configured\n"
      )
    }
  }

  private func jsonResult(_ value: some Encodable) -> OmapetCommandResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      let data = try encoder.encode(value)
      return OmapetCommandResult(
        exitCode: 0,
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

private struct SetupStatusOutput: Encodable {
  let status: String
  let connections: [String]
}
