import Foundation
import XCTest

@testable import AgentPetUI

@MainActor
final class OverlayPreferencesStoreTests: XCTestCase {
  func testDefaultsAndRoundTrip() throws {
    let defaults = try isolatedDefaults()
    let store = OverlayPreferencesStore(defaults: defaults)

    XCTAssertEqual(store.load(), OverlayPreferences())

    let saved = OverlayPreferences(
      isVisible: false,
      cardMode: .many,
      position: OverlayPosition(x: 120, y: 240)
    )
    store.save(saved)

    XCTAssertEqual(store.load(), saved)
    XCTAssertEqual(
      defaults.integer(forKey: "overlay.schemaVersion"),
      OverlayPreferencesStore.currentSchemaVersion
    )
  }

  func testUnknownFutureSchemaFallsBackWithoutRewriting() throws {
    let defaults = try isolatedDefaults()
    defaults.set(99, forKey: "overlay.schemaVersion")
    defaults.set(false, forKey: "overlay.isVisible")
    defaults.set("many", forKey: "overlay.cardMode")
    let store = OverlayPreferencesStore(defaults: defaults)

    XCTAssertEqual(store.load(), OverlayPreferences())
    store.save(OverlayPreferences(isVisible: true, cardMode: .none))
    XCTAssertEqual(defaults.integer(forKey: "overlay.schemaVersion"), 99)
    XCTAssertEqual(defaults.string(forKey: "overlay.cardMode"), "many")
  }

  func testInvalidModeFallsBackToOne() throws {
    let defaults = try isolatedDefaults()
    defaults.set(1, forKey: "overlay.schemaVersion")
    defaults.set("invalid", forKey: "overlay.cardMode")

    XCTAssertEqual(OverlayPreferencesStore(defaults: defaults).load().cardMode, .one)
  }

  func testNonFinitePositionIsDiscarded() throws {
    let defaults = try isolatedDefaults()
    defaults.set(1, forKey: "overlay.schemaVersion")
    defaults.set(Double.nan, forKey: "overlay.position.x")
    defaults.set(Double.infinity, forKey: "overlay.position.y")

    XCTAssertNil(OverlayPreferencesStore(defaults: defaults).load().position)
  }

  private func isolatedDefaults() throws -> UserDefaults {
    let suiteName = "OverlayPreferencesStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
    return defaults
  }
}
