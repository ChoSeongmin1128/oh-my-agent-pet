import Darwin
import Foundation
import OmapetSupport

let arguments = Array(CommandLine.arguments.dropFirst())
let standardInput: Data
if arguments == ["hook", "claude"] {
  standardInput = readHookInput(
    from: FileHandle.standardInput,
    maximumBytes: OmapetCommandRunner.maximumHookInputBytes
  )
} else {
  standardInput = Data()
}

let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let result = OmapetCommandRunner(executableURL: executableURL).run(
  arguments: arguments,
  standardInput: standardInput
)

if let output = result.standardOutput.data(using: .utf8) {
  FileHandle.standardOutput.write(output)
}
if let error = result.standardError.data(using: .utf8) {
  FileHandle.standardError.write(error)
}

exit(result.exitCode)

private func readHookInput(from handle: FileHandle, maximumBytes: Int) -> Data {
  var captured = Data()
  while let chunk = try? handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
    if captured.count <= maximumBytes {
      let remaining = maximumBytes + 1 - captured.count
      captured.append(chunk.prefix(remaining))
    }
  }
  return captured
}
