import AgentPetCodex
import Foundation
import XCTest

final class CodexFileSetWatcherTests: XCTestCase {
  func testObservesAppendAndDirectoryCreation() throws {
    let directory = temporaryDirectory()
    let file = directory.appendingPathComponent("rollout.jsonl")
    try Data("first\n".utf8).write(to: file)
    let appended = expectation(description: "appended")
    let created = expectation(description: "created")
    let probe = FileSetProbe(appended: appended, created: created)
    let watcher = CodexFileSetWatcher { probe.recordChange() }
    watcher.start(urls: [directory, file])
    addTeardownBlock { watcher.stop() }

    probe.armForAppend()
    try append(Data("second\n".utf8), to: file)
    wait(for: [appended], timeout: 3)
    probe.armForCreate()
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("next-day"), withIntermediateDirectories: false)
    wait(for: [created], timeout: 3)
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

private final class FileSetProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let appended: XCTestExpectation
  private let created: XCTestExpectation
  private var phase = 0

  init(appended: XCTestExpectation, created: XCTestExpectation) {
    self.appended = appended
    self.created = created
  }

  func armForAppend() { setPhase(1) }
  func armForCreate() { setPhase(3) }

  func recordChange() {
    lock.lock()
    let expectation: XCTestExpectation?
    switch phase {
    case 1:
      phase = 2
      expectation = appended
    case 3:
      phase = 4
      expectation = created
    default:
      expectation = nil
    }
    lock.unlock()
    expectation?.fulfill()
  }

  private func setPhase(_ value: Int) {
    lock.lock()
    phase = value
    lock.unlock()
  }
}
