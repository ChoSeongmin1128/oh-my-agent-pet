import Darwin
import Foundation

public enum ClaudeHookRecordResult: Equatable, Sendable {
  case recorded
  case ignored
}

public enum ClaudeHookRecorderError: Error, Equatable, Sendable {
  case inputTooLarge
  case invalidJSON
  case storageUnavailable
  case unsafeStorageTarget
  case partialWrite
}

public struct ClaudeHookRecorder: Sendable {
  public static let maximumInputBytes = 8 * 1_024 * 1_024

  public let eventsURL: URL

  public init(applicationSupportDirectory: URL) {
    eventsURL = applicationSupportDirectory.appendingPathComponent("events.ndjson")
  }

  public func record(
    input: Data,
    now: Date = Date(),
    recordID: UUID = UUID()
  ) throws -> ClaudeHookRecordResult {
    guard input.count <= Self.maximumInputBytes else {
      throw ClaudeHookRecorderError.inputTooLarge
    }

    let payload: ClaudeHookInput
    do {
      payload = try JSONDecoder().decode(ClaudeHookInput.self, from: input)
    } catch {
      throw ClaudeHookRecorderError.invalidJSON
    }

    guard
      let event = ClaudeHookEventPolicy.storedEvent(
        from: payload,
        now: now,
        recordID: recordID
      )
    else {
      return .ignored
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var line = try encoder.encode(event)
    line.append(0x0A)
    try append(line)
    return .recorded
  }

  private func append(_ data: Data) throws {
    let directory = eventsURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: UInt16(0o700))],
        ofItemAtPath: directory.path
      )
    } catch {
      throw ClaudeHookRecorderError.storageUnavailable
    }

    let descriptor = eventsURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(
        path,
        O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
      )
    }
    guard descriptor >= 0 else {
      if errno == ELOOP {
        throw ClaudeHookRecorderError.unsafeStorageTarget
      }
      throw ClaudeHookRecorderError.storageUnavailable
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      throw ClaudeHookRecorderError.unsafeStorageTarget
    }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw ClaudeHookRecorderError.storageUnavailable
    }

    let written = data.withUnsafeBytes { bytes -> Int in
      guard let address = bytes.baseAddress else { return 0 }
      return Darwin.write(descriptor, address, bytes.count)
    }
    guard written == data.count else {
      throw ClaudeHookRecorderError.partialWrite
    }
  }
}
