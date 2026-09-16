import AgentPetClaude
import Foundation
import XCTest

final class ClaudeEventLogWatcherTests: XCTestCase {
  func testObservesFileCreationAndAppend() throws {
    let directory = temporaryDirectory().appendingPathComponent("support")
    let url = directory.appendingPathComponent("events.ndjson")
    let created = expectation(description: "created")
    let appended = expectation(description: "appended")
    let probe = WatcherProbe(created: created, appended: appended)
    let watcher = ClaudeEventLogWatcher(eventsURL: url) {
      probe.recordChange()
    }
    try watcher.start()
    addTeardownBlock { watcher.stop() }

    try Data("first\n".utf8).write(to: url)
    wait(for: [created], timeout: 3)
    probe.armForAppend()
    try append(Data("second\n".utf8), to: url)
    wait(for: [appended], timeout: 3)
  }

  private func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.close()
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

private final class WatcherProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let created: XCTestExpectation
  private let appended: XCTestExpectation
  private var phase = 0

  init(created: XCTestExpectation, appended: XCTestExpectation) {
    self.created = created
    self.appended = appended
  }

  func recordChange() {
    lock.lock()
    let expectation: XCTestExpectation?
    if phase == 0 {
      phase = 1
      expectation = created
    } else if phase == 2 {
      phase = 3
      expectation = appended
    } else {
      expectation = nil
    }
    lock.unlock()
    expectation?.fulfill()
  }

  func armForAppend() {
    lock.lock()
    phase = 2
    lock.unlock()
  }
}
