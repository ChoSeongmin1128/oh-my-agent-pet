import Darwin
import Foundation

public final class AgentFileSetWatcher: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.seongmin.OhMyAgentPet.file-set-watcher")
  private let queueKey = DispatchSpecificKey<UInt8>()
  private let onChange: @Sendable () -> Void
  private var sources: [URL: DispatchSourceFileSystemObject] = [:]
  private var pendingNotification: DispatchWorkItem?
  private var started = false

  public init(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange
    queue.setSpecific(key: queueKey, value: 1)
  }

  public func start(urls: [URL]) {
    syncOnQueue {
      guard !started else { return }
      started = true
      replaceSources(with: Set(urls))
    }
  }

  public func update(urls: [URL]) {
    syncOnQueue {
      guard started else { return }
      replaceSources(with: Set(urls))
    }
  }

  public func stop() {
    syncOnQueue {
      guard started else { return }
      started = false
      pendingNotification?.cancel()
      pendingNotification = nil
      for source in sources.values { source.cancel() }
      sources.removeAll()
    }
  }

  deinit {
    for source in sources.values { source.cancel() }
  }

  private func replaceSources(with urls: Set<URL>) {
    for url in Set(sources.keys).subtracting(urls) {
      sources.removeValue(forKey: url)?.cancel()
    }
    for url in urls where sources[url] == nil {
      installSource(for: url)
    }
  }

  private func installSource(for url: URL) {
    let descriptor = url.withUnsafeFileSystemRepresentation { filePath -> Int32 in
      guard let filePath else { return -1 }
      return Darwin.open(filePath, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
      fileStatus.st_mode & S_IFMT == S_IFREG || fileStatus.st_mode & S_IFMT == S_IFDIR
    else {
      Darwin.close(descriptor)
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
      queue: queue
    )
    source.setEventHandler { [weak self, weak source] in
      guard let self, let source, self.started else { return }
      let events = source.data
      if events.contains(.rename) || events.contains(.delete) || events.contains(.revoke) {
        self.sources.removeValue(forKey: url)?.cancel()
      }
      self.scheduleNotification()
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    sources[url] = source
    source.resume()
  }

  private func syncOnQueue(_ operation: () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) == 1 {
      operation()
    } else {
      queue.sync(execute: operation)
    }
  }

  private func scheduleNotification() {
    pendingNotification?.cancel()
    let notification = DispatchWorkItem { [weak self] in
      guard let self, self.started else { return }
      self.pendingNotification = nil
      self.onChange()
    }
    pendingNotification = notification
    queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: notification)
  }
}
