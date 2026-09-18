import Foundation

public enum OmapetCommand: Equatable, Sendable {
  case help
  case version(json: Bool)
  case doctor(json: Bool)
  case setupStatus(json: Bool)
  case setupStatusCodex(json: Bool)
  case setupConnectClaude(json: Bool, dryRun: Bool)
  case setupDisconnectClaude(json: Bool, dryRun: Bool)
  case setupConnectCodex(json: Bool, dryRun: Bool)
  case setupDisconnectCodex(json: Bool, dryRun: Bool)
  case hookClaude
  case hookCodex
  case petList(json: Bool)
  case petInspect(source: String, json: Bool)
  case petInstall(source: String, json: Bool, dryRun: Bool)
  case petSelect(identifier: String, json: Bool)
  case petRemove(recordID: String, json: Bool)
}

enum OmapetCommandParser {
  static func parse(arguments: [String]) throws -> OmapetCommand {
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
    case ["setup", "status"] where !dryRun,
      ["setup", "status", "claude"] where !dryRun:
      return .setupStatus(json: json)
    case ["setup", "status", "codex"] where !dryRun:
      return .setupStatusCodex(json: json)
    case ["setup", "connect", "claude"]:
      return .setupConnectClaude(json: json, dryRun: dryRun)
    case ["setup", "disconnect", "claude"]:
      return .setupDisconnectClaude(json: json, dryRun: dryRun)
    case ["setup", "connect", "codex"]:
      return .setupConnectCodex(json: json, dryRun: dryRun)
    case ["setup", "disconnect", "codex"]:
      return .setupDisconnectCodex(json: json, dryRun: dryRun)
    case ["hook", "claude"] where !json && !dryRun:
      return .hookClaude
    case ["hook", "codex"] where !json && !dryRun:
      return .hookCodex
    case ["pet", "list"] where !dryRun:
      return .petList(json: json)
    default:
      if positional.count == 3, positional[0] == "pet" {
        switch positional[1] {
        case "inspect" where !dryRun:
          return .petInspect(source: positional[2], json: json)
        case "install":
          return .petInstall(source: positional[2], json: json, dryRun: dryRun)
        case "select" where !dryRun:
          return .petSelect(identifier: positional[2], json: json)
        case "remove" where !dryRun:
          return .petRemove(recordID: positional[2], json: json)
        default:
          break
        }
      }
      throw OmapetCLIError.unsupportedArguments(positional)
    }
  }
}

enum OmapetCLIError: Error, CustomStringConvertible {
  case unsupportedArguments([String])

  var description: String {
    switch self {
    case .unsupportedArguments(let arguments):
      return "Unsupported arguments: \(arguments.joined(separator: " "))"
    }
  }
}
