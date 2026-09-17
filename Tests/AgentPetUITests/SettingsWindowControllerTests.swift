import AgentPetLibrary
import AgentPetTestSupport
import AppKit
import XCTest

@testable import AgentPetUI

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUpWithError() throws {
    root = try PetPackageFixture.temporaryDirectory(prefix: "omapet-settings")
    suiteName = "SettingsWindowControllerTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: root)
  }

  private func makeController() -> SettingsWindowController {
    let service = PetLibraryService(paths: PetLibraryPaths(applicationSupportDirectory: root))
    let model = SettingsModel(petLibrary: PetLibraryViewModel(service: service) {})
    return SettingsWindowController(model: model, defaults: defaults)
  }

  func testShowReusesWindowAndCloseDiscardsHostingTree() throws {
    let controller = makeController()
    XCTAssertNil(controller.hostingController)
    XCTAssertEqual(controller.model.pane, .general)

    controller.show(pane: .pet)
    let firstHosting = try XCTUnwrap(controller.hostingController)
    XCTAssertTrue(controller.isWindowVisible)
    XCTAssertEqual(controller.model.pane, .pet)

    controller.show()
    XCTAssertTrue(controller.hostingController === firstHosting, "second show reuses the window")

    let window = try XCTUnwrap(firstHosting.view.window)
    window.close()
    XCTAssertNil(controller.hostingController, "closing releases the SwiftUI tree")
    XCTAssertFalse(controller.isWindowVisible)
    XCTAssertEqual(defaults.string(forKey: SettingsWindowController.lastPaneKey), "pet")

    controller.show()
    XCTAssertEqual(controller.model.pane, .pet, "last pane is restored")
    XCTAssertFalse(controller.hostingController === firstHosting, "a fresh tree is built")
    controller.hostingController?.view.window?.close()
  }

  func testUnavailablePaneFallsBackToGeneral() {
    defaults.set(SettingsPane.connections.rawValue, forKey: SettingsWindowController.lastPaneKey)
    let controller = makeController()
    XCTAssertEqual(controller.model.pane, .general)
    controller.show(pane: .privacyDiagnostics)
    XCTAssertEqual(controller.model.pane, .general)
    controller.hostingController?.view.window?.close()
    XCTAssertNil(controller.hostingController)
  }
}
