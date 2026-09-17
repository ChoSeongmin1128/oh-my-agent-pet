import AgentPetLibrary
import AgentPetTestSupport
import Foundation
import XCTest

@testable import AgentPetUI

@MainActor
final class PetLibraryViewModelTests: XCTestCase {
  private var root: URL!
  private var service: PetLibraryService!
  private var changes = 0

  override func setUpWithError() throws {
    root = try PetPackageFixture.temporaryDirectory(prefix: "omapet-viewmodel")
    service = PetLibraryService(
      paths: PetLibraryPaths(applicationSupportDirectory: root.appendingPathComponent("support")))
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: root)
  }

  private func makeModel() -> PetLibraryViewModel {
    PetLibraryViewModel(service: service) { [weak self] in self?.changes += 1 }
  }

  func testRowsListOriginalInstalledAndNoneWithSelection() async throws {
    let source = try PetPackageFixture.writePackage(
      into: root.appendingPathComponent("src"), id: "row-pet", displayName: "Row Pet")
    _ = try service.install(try service.stage(.folder(source)))
    let model = makeModel()

    await model.refresh()

    XCTAssertEqual(model.rows.map(\.id), ["original", "row-pet", "none"])
    XCTAssertEqual(model.rows[1].title, "Row Pet")
    XCTAssertEqual(model.rows[1].subtitle, "Folder: src")
    XCTAssertEqual(model.rows[1].licenseStatus, .unknown)
    XCTAssertEqual(model.selection, .original)
    XCTAssertNil(model.previewPackage)
    XCTAssertNotNil(model.thumbnails["row-pet"])

    await model.select(.installed(recordID: "row-pet"))
    XCTAssertEqual(model.selection, .installed(recordID: "row-pet"))
    XCTAssertNotNil(model.previewPackage)
    XCTAssertEqual(changes, 1)

    await model.select(.installed(recordID: "row-pet"))
    XCTAssertEqual(changes, 1, "unchanged selection does not notify")

    await model.select(.none)
    XCTAssertEqual(model.selection, .none)
    XCTAssertNil(model.previewPackage)
    XCTAssertEqual(changes, 2)
  }

  func testReviewInstallUseNowAndRemove() async throws {
    let source = try PetPackageFixture.writePackage(
      into: root.appendingPathComponent("incoming"), id: "incoming", version: 2)
    let model = makeModel()
    await model.refresh()

    await model.stage(.folder(source))
    let review = try XCTUnwrap(model.review)
    XCTAssertEqual(review.inspection.manifestID, "incoming")
    XCTAssertEqual(service.entries().count, 0, "review does not install")

    await model.installReviewedPackage(useNow: true)
    XCTAssertNil(model.review)
    XCTAssertEqual(model.rows.map(\.id), ["original", "incoming", "none"])
    XCTAssertEqual(model.selection, .installed(recordID: "incoming"))
    XCTAssertEqual(changes, 1)

    await model.remove(recordID: "incoming")
    XCTAssertEqual(model.rows.map(\.id), ["original", "none"])
    XCTAssertEqual(model.selection, .original)
    XCTAssertEqual(changes, 2)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: source.appendingPathComponent("pet.json").path))
  }

  func testCancelledReviewCleansStageAndErrorsSurfaceAsMessages() async throws {
    let broken = root.appendingPathComponent("broken")
    try PetPackageFixture.writePackage(into: broken, id: "broken", version: 1, rows: 11)
    let model = makeModel()

    await model.stage(.folder(broken))
    XCTAssertNil(model.review)
    XCTAssertEqual(
      model.errorMessage, "The spritesheet size does not match the declared sprite version.")
    model.errorMessage = nil

    let good = try PetPackageFixture.writePackage(
      into: root.appendingPathComponent("good"), id: "good")
    await model.stage(.folder(good))
    XCTAssertNotNil(model.review)
    model.windowDidClose()
    XCTAssertNil(model.review)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: service.paths.stagingDirectory.path), [])
    XCTAssertEqual(changes, 0)
  }

  func testDamagedSelectionShowsIssueAndKeepsCardsAvailable() async throws {
    let source = try PetPackageFixture.writePackage(
      into: root.appendingPathComponent("frag"), id: "frag")
    let record = try service.install(try service.stage(.folder(source))).record
    _ = try service.select(.installed(recordID: record.recordID))
    try FileManager.default.removeItem(at: service.paths.recordDirectory(for: record.recordID))
    let model = makeModel()

    await model.refresh()

    XCTAssertEqual(model.selectionIssue, .recordMissing(recordID: "frag"))
    XCTAssertNil(model.previewPackage)
    XCTAssertEqual(model.rows.map(\.id), ["original", "none"])
    await model.select(.original)
    XCTAssertNil(model.selectionIssue)
  }
}
