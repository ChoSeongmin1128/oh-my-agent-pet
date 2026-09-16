import Darwin
import Foundation

public enum AgentHookRecordResult: Equatable, Sendable {
  case recorded
  case ignored
}

public enum AgentHookRecorderError: Error, Equatable, Sendable {
  case inputTooLarge
  case invalidJSON
  case storageUnavailable
  case unsafeStorageTarget
  case partialWrite
}

public struct AgentHookRecorder: Sendable {
  public static let maximumInputBytes = 8 * 1_024 * 1_024

  public let provider: AgentHookProvider
  public let eventsURL: URL

  public init(
    provider: AgentHookProvider = .claude,
    applicationSupportDirectory: URL
  ) {
    self.provider = provider
    eventsURL = applicationSupportDirectory.appendingPathComponent("events.ndjson")
  }

  public func record(
    input: Data,
    now: Date = Date(),
    recordID: UUID = UUID(),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    tty: String? = AgentHookExecutionContext.controllingTTY()
  ) throws -> AgentHookRecordResult {
    guard input.count <= Self.maximumInputBytes else {
      throw AgentHookRecorderError.inputTooLarge
    }

    let payload: AgentHookInput
    do {
      payload = try JSONDecoder().decode(AgentHookInput.self, from: input)
    } catch {
      throw AgentHookRecorderError.invalidJSON
    }

    guard
      let event = AgentHookEventPolicy.storedEvent(
        from: payload,
        provider: provider,
        environment: environment,
        tty: tty,
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
      throw AgentHookRecorderError.storageUnavailable
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
        throw AgentHookRecorderError.unsafeStorageTarget
      }
      throw AgentHookRecorderError.storageUnavailable
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG
    else {
      throw AgentHookRecorderError.unsafeStorageTarget
    }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw AgentHookRecorderError.storageUnavailable
    }

    let written = data.withUnsafeBytes { bytes -> Int in
      guard let baseAddress = bytes.baseAddress else { return 0 }
      return Darwin.write(descriptor, baseAddress, bytes.count)
    }
    guard written == data.count else { throw AgentHookRecorderError.partialWrite }
  }
}

public enum AgentHookExecutionContext {
  public static func controllingTTY() -> String? {
    let descriptor = Darwin.open("/dev/tty", O_RDONLY | O_NOCTTY | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    defer { Darwin.close(descriptor) }
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard ttyname_r(descriptor, &buffer, buffer.count) == 0 else { return nil }
    return String(
      decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
      as: UTF8.self
    )
  }
}
