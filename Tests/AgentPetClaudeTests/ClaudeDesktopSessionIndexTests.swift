import Foundation
import XCTest

@testable import AgentPetClaude

final class ClaudeDesktopSessionIndexTests: XCTestCase {
  func testBuildsLatestNonArchivedRouteWithoutReadingUnrelatedFields() throws {
    let directory = temporaryDirectory()
    let nested = directory.appendingPathComponent("a/b", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try metadata(
      desktop: "local_11111111-1111-1111-1111-111111111111",
      cli: "cli-session",
      activity: 10,
      archived: false
    ).write(to: nested.appendingPathComponent("old.json"))
    try metadata(
      desktop: "local_22222222-2222-2222-2222-222222222222",
      cli: "cli-session",
      activity: 20,
      archived: false
    ).write(to: nested.appendingPathComponent("new.json"))
    try metadata(
      desktop: "local_33333333-3333-3333-3333-333333333333",
      cli: "archived",
      activity: 30,
      archived: true
    ).write(to: nested.appendingPathComponent("archived.json"))
    var index = ClaudeDesktopSessionIndex(sessionsDirectory: directory)

    let routes = index.routes()

    XCTAssertEqual(
      routes["cli-session"],
      "local_22222222-2222-2222-2222-222222222222"
    )
    XCTAssertNil(routes["archived"])
  }

  func testDetectsReplacementAndRejectsSymlink() throws {
    let directory = temporaryDirectory()
    let routeURL = directory.appendingPathComponent("route.json")
    try metadata(
      desktop: "local_11111111-1111-1111-1111-111111111111",
      cli: "cli-session",
      activity: 10,
      archived: false
    ).write(to: routeURL)
    let target = directory.appendingPathComponent("target.txt")
    try metadata(
      desktop: "local_99999999-9999-9999-9999-999999999999",
      cli: "symlink",
      activity: 100,
      archived: false
    ).write(to: target)
    try FileManager.default.createSymbolicLink(
      at: directory.appendingPathComponent("link.json"),
      withDestinationURL: target
    )
    var index = ClaudeDesktopSessionIndex(sessionsDirectory: directory)
    _ = index.routes()

    try metadata(
      desktop: "local_22222222-2222-2222-2222-222222222222",
      cli: "cli-session",
      activity: 20,
      archived: false
    ).write(to: routeURL, options: .atomic)
    let routes = index.routes()

    XCTAssertEqual(
      routes["cli-session"],
      "local_22222222-2222-2222-2222-222222222222"
    )
    XCTAssertNil(routes["symlink"])
  }

  private func metadata(
    desktop: String,
    cli: String,
    activity: Int,
    archived: Bool
  ) -> Data {
    Data(
      """
      {"sessionId":"\(desktop)","cliSessionId":"\(cli)","lastActivityAt":\(activity),"isArchived":\(archived),"promptAppendSnapshot":"secret"}
      """.utf8
    )
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
