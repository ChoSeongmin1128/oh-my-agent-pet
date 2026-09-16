import Darwin
import Foundation
import OmapetSupport

let result = OmapetCommandRunner().run(arguments: Array(CommandLine.arguments.dropFirst()))

if let output = result.standardOutput.data(using: .utf8) {
  FileHandle.standardOutput.write(output)
}
if let error = result.standardError.data(using: .utf8) {
  FileHandle.standardError.write(error)
}

exit(result.exitCode)
