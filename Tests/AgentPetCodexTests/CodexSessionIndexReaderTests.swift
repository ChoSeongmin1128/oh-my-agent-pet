import AgentPetCodex
import Foundation
import XCTest

final class CodexSessionIndexReaderTests: XCTestCase {
  func testMissingIndexIsEmptyAndThenUnchanged() throws {
    var reader = CodexSessionIndexReader(
      indexURL: temporaryDirectory().appendingPathComponent("index"))

    let first = try reader.readIfChanged()
    let second = try reader.readIfChanged()

    XCTAssertTrue(first.didChange)
    XCTAssertEqual(first.entries, [])
    XCTAssertFalse(second.didChange)
  }

  func testParsesLatestEntryPerIDAndSkipsInvalidRecord() throws {
    let url = temporaryDirectory().appendingPathComponent("session_index.jsonl")
    let id = "01A0AA42-19A8-78D0-8535-1C9D8782ABB7"
    let contents = """
      {"id":"\(id)","thread_name":"Old title","updated_at":"2026-09-16T10:00:00Z"}
      broken
      {"id":"\(id)","thread_name":"New title","updated_at":"2026-09-16T11:00:00.123456Z"}

      """
    try Data(contents.utf8).write(to: url)
    var reader = CodexSessionIndexReader(indexURL: url)

    let result = try reader.readIfChanged()

    XCTAssertEqual(result.entries.count, 1)
    XCTAssertEqual(result.entries.first?.id, id.lowercased())
    XCTAssertEqual(result.entries.first?.title, "New title")
    XCTAssertEqual(result.issues, [.invalidRecord])
    XCTAssertFalse(try reader.readIfChanged().didChange)
  }

  func testReplacementIsDetected() throws {
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("session_index.jsonl")
    try indexLine(id: 1, title: "One", second: 1).write(to: url)
    var reader = CodexSessionIndexReader(indexURL: url)
    _ = try reader.readIfChanged()

    let replacement = directory.appendingPathComponent("replacement")
    try indexLine(id: 2, title: "Two", second: 2).write(to: replacement)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: replacement, to: url)

    let result = try reader.readIfChanged()

    XCTAssertTrue(result.didChange)
    XCTAssertEqual(result.entries.map(\.title), ["Two"])
  }

  func testRejectsSymbolicLink() throws {
    let directory = temporaryDirectory()
    let target = directory.appendingPathComponent("target")
    let link = directory.appendingPathComponent("session_index.jsonl")
    try indexLine(id: 1, title: "One", second: 1).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    var reader = CodexSessionIndexReader(indexURL: link)

    XCTAssertThrowsError(try reader.readIfChanged()) {
      XCTAssertEqual($0 as? CodexSessionIndexError, .unsafeFile)
    }
  }

  private func indexLine(id: Int, title: String, second: Int) -> Data {
    Data(
      "{\"id\":\"\(uuid(id))\",\"thread_name\":\"\(title)\",\"updated_at\":\"2026-09-16T10:00:\(String(format: "%02d", second))Z\"}\n"
        .utf8
    )
  }

  private func uuid(_ value: Int) -> String {
    String(format: "00000000-0000-0000-0000-%012d", value)
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
