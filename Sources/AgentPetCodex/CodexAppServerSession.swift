import AgentPetCore
import Darwin
import Foundation

protocol CodexAppServerSessionProtocol: AnyObject, Sendable {
  func call(method: String, params: [String: Any]) throws -> [String: Any]
  func close()
}

final class CodexAppServerSession: CodexAppServerSessionProtocol, @unchecked Sendable {
  enum Error: Swift.Error {
    case timedOut(String)
    case streamClosed
    case invalidResponse
    case server(code: Int?, message: String)
  }

  private let process = Process()
  private let inputPipe = Pipe()
  private let outputPipe = Pipe()
  private let errorPipe = Pipe()
  private let inputWriter: CodexAppServerInputWriter
  private let responses = CodexAppServerResponseBuffer()
  private let timeout: TimeInterval
  private var nextRequestID = 1
  private var isClosed = false

  init(
    executableURL: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timeout: TimeInterval = 5
  ) throws {
    self.timeout = timeout
    inputWriter = try CodexAppServerInputWriter(fileHandle: inputPipe.fileHandleForWriting)
    process.executableURL = executableURL
    process.arguments = ["app-server"]
    process.environment = environment
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { [responses] handle in
      let data = handle.availableData
      data.isEmpty ? responses.markClosed() : responses.append(data)
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      _ = handle.availableData
    }

    do {
      try process.run()
      _ = try call(
        method: "initialize",
        params: [
          "clientInfo": [
            "name": "oh-my-agent-pet",
            "title": AgentPetProduct.name,
            "version": AgentPetProduct.developmentVersion,
          ],
          "capabilities": ["experimentalApi": true],
        ]
      )
      try send(["method": "initialized", "params": [:]])
    } catch {
      close()
      throw error
    }
  }

  func call(method: String, params: [String: Any]) throws -> [String: Any] {
    let requestID = nextRequestID
    nextRequestID += 1
    try send(["id": requestID, "method": method, "params": params])
    guard let response = try responses.wait(for: requestID, timeout: timeout) else {
      throw Error.timedOut(method)
    }
    if let error = response["error"] as? [String: Any] {
      throw Error.server(
        code: (error["code"] as? NSNumber)?.intValue,
        message: error["message"] as? String ?? "Codex app-server request failed."
      )
    }
    guard let result = response["result"] as? [String: Any] else {
      throw Error.invalidResponse
    }
    return result
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
    inputWriter.close()
    if process.isRunning { process.terminate() }
  }

  deinit { close() }

  private func send(_ object: [String: Any]) throws {
    guard JSONSerialization.isValidJSONObject(object) else { throw Error.invalidResponse }
    var data = try JSONSerialization.data(withJSONObject: object)
    data.append(0x0A)
    try inputWriter.write(data)
  }
}

private final class CodexAppServerInputWriter: @unchecked Sendable {
  enum Error: Swift.Error { case closed }

  private let fileHandle: FileHandle
  private let descriptor: Int32
  private let lock = NSLock()
  private var isClosed = false

  init(fileHandle: FileHandle) throws {
    self.fileHandle = fileHandle
    descriptor = fileHandle.fileDescriptor
    guard fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  func write(_ data: Data) throws {
    try lock.withLock {
      guard !isClosed else { throw Error.closed }
      try data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        var written = 0
        while written < bytes.count {
          let count = Darwin.write(
            descriptor,
            baseAddress.advanced(by: written),
            bytes.count - written
          )
          if count > 0 {
            written += count
          } else if count == -1, errno == EINTR {
            continue
          } else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
          }
        }
      }
    }
  }

  func close() {
    lock.withLock {
      guard !isClosed else { return }
      isClosed = true
      try? fileHandle.close()
    }
  }

  deinit { close() }
}

private final class CodexAppServerResponseBuffer: @unchecked Sendable {
  private let condition = NSCondition()
  private var bufferedData = Data()
  private var responses: [Int: [String: Any]] = [:]
  private var isClosed = false

  func append(_ data: Data) {
    condition.lock()
    bufferedData.append(data)
    while let newline = bufferedData.firstIndex(of: 0x0A) {
      let line = bufferedData[..<newline]
      bufferedData.removeSubrange(...newline)
      guard !line.isEmpty,
        let object = try? JSONSerialization.jsonObject(with: Data(line)),
        let response = object as? [String: Any],
        let requestID = (response["id"] as? NSNumber)?.intValue
      else { continue }
      responses[requestID] = response
    }
    condition.broadcast()
    condition.unlock()
  }

  func markClosed() {
    condition.lock()
    isClosed = true
    condition.broadcast()
    condition.unlock()
  }

  func wait(for requestID: Int, timeout: TimeInterval) throws -> [String: Any]? {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(timeout)
    while responses[requestID] == nil, !isClosed {
      guard condition.wait(until: deadline) else { break }
    }
    if let response = responses.removeValue(forKey: requestID) { return response }
    if isClosed { throw CodexAppServerSession.Error.streamClosed }
    return nil
  }
}
