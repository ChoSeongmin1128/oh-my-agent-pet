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
  public static let maximumEventLogBytes = 8 * 1_024 * 1_024

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

    let lockURL = directory.appendingPathComponent(".events.lock")
    let lockDescriptor = lockURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(
        path,
        O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
      )
    }
    guard lockDescriptor >= 0 else {
      if errno == ELOOP {
        throw AgentHookRecorderError.unsafeStorageTarget
      }
      throw AgentHookRecorderError.storageUnavailable
    }
    defer {
      flock(lockDescriptor, LOCK_UN)
      Darwin.close(lockDescriptor)
    }
    var lockStatus = stat()
    guard fstat(lockDescriptor, &lockStatus) == 0,
      lockStatus.st_mode & S_IFMT == S_IFREG,
      fchmod(lockDescriptor, S_IRUSR | S_IWUSR) == 0,
      flock(lockDescriptor, LOCK_EX) == 0
    else {
      throw AgentHookRecorderError.unsafeStorageTarget
    }

    try rotateIfNeeded(in: directory, incomingBytes: data.count)

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

    guard writeAll(data, to: descriptor) else { throw AgentHookRecorderError.partialWrite }
  }

  private func rotateIfNeeded(in directory: URL, incomingBytes: Int) throws {
    guard FileManager.default.fileExists(atPath: eventsURL.path) else { return }
    var fileStatus = stat()
    let statusResult = eventsURL.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &fileStatus)
    }
    guard statusResult == 0 else {
      throw AgentHookRecorderError.storageUnavailable
    }
    guard fileStatus.st_mode & S_IFMT == S_IFREG else {
      throw AgentHookRecorderError.unsafeStorageTarget
    }
    guard Int(fileStatus.st_size) + incomingBytes > Self.maximumEventLogBytes else { return }

    let rotatedURL = directory.appendingPathComponent("events.ndjson.1")
    do {
      if FileManager.default.fileExists(atPath: rotatedURL.path) {
        var rotatedStatus = stat()
        let result = rotatedURL.withUnsafeFileSystemRepresentation { path -> Int32 in
          guard let path else { return -1 }
          return lstat(path, &rotatedStatus)
        }
        guard result == 0, rotatedStatus.st_mode & S_IFMT == S_IFREG else {
          throw AgentHookRecorderError.unsafeStorageTarget
        }
        try FileManager.default.removeItem(at: rotatedURL)
      }
      try FileManager.default.moveItem(at: eventsURL, to: rotatedURL)
    } catch let error as AgentHookRecorderError {
      throw error
    } catch {
      throw AgentHookRecorderError.storageUnavailable
    }
  }

  private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return data.isEmpty }
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if written > 0 {
          offset += written
          continue
        }
        if written < 0, errno == EINTR {
          continue
        }
        return false
      }
      return true
    }
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
