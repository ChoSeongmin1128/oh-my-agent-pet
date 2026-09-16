import Darwin
import Foundation

public final class AgentEventLogWatcher: @unchecked Sendable {
  private let eventsURL: URL
  private let queue = DispatchQueue(label: "com.seongmin.OhMyAgentPet.agent-event-watcher")
  private let queueKey = DispatchSpecificKey<UInt8>()
  private let onChange: @Sendable () -> Void

  private var parentSource: DispatchSourceFileSystemObject?
  private var fileSource: DispatchSourceFileSystemObject?
  private var started = false

  public init(eventsURL: URL, onChange: @escaping @Sendable () -> Void) {
    self.eventsURL = eventsURL
    self.onChange = onChange
    queue.setSpecific(key: queueKey, value: 1)
  }

  public func start() throws {
    let directory = eventsURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: UInt16(0o700))],
      ofItemAtPath: directory.path
    )
    syncOnQueue {
      guard !started else { return }
      started = true
      installParentSource()
      installFileSource()
    }
  }

  public func stop() {
    syncOnQueue {
      guard started else { return }
      started = false
      parentSource?.cancel()
      parentSource = nil
      fileSource?.cancel()
      fileSource = nil
    }
  }

  deinit {
    parentSource?.cancel()
    fileSource?.cancel()
  }

  private func syncOnQueue(_ operation: () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) == 1 {
      operation()
    } else {
      queue.sync(execute: operation)
    }
  }

  private func installParentSource() {
    let directory = eventsURL.deletingLastPathComponent()
    let descriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_EVTONLY | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete, .revoke],
      queue: queue
    )
    source.setEventHandler { [weak self] in
      guard let self, self.started else { return }
      self.installFileSource()
      self.onChange()
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    parentSource = source
    source.resume()
  }

  private func installFileSource() {
    fileSource?.cancel()
    fileSource = nil

    let descriptor = eventsURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .rename, .delete, .revoke],
      queue: queue
    )
    source.setEventHandler { [weak self, weak source] in
      guard let self, let source, self.started else { return }
      let events = source.data
      self.onChange()
      if events.contains(.rename) || events.contains(.delete) || events.contains(.revoke) {
        self.installFileSource()
      }
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    fileSource = source
    source.resume()
  }
}
