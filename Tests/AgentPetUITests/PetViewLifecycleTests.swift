import AgentPetSprites
import AgentPetTestSupport
import AppKit
import XCTest

@testable import AgentPetUI

@MainActor
final class PetViewLifecycleTests: XCTestCase {
  func testAnimationAndMouseMonitorsStopWhenViewLeavesWindow() throws {
    let directory = try PetPackageFixture.writePackage(
      into: try PetPackageFixture.temporaryDirectory(), id: "lifecycle", version: 2)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try PetSpritePackageLoader().load(packageDirectory: directory)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let petView = PetView(frame: NSRect(x: 0, y: 0, width: 78, height: 78))
    petView.setSpritePackage(package)
    petView.update(with: .preview(status: .ready))

    XCTAssertFalse(petView.isAnimating, "no window, no timer")
    XCTAssertFalse(petView.hasMouseMonitors)

    window.contentView?.addSubview(petView)
    XCTAssertTrue(petView.isAnimating)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      XCTAssertTrue(petView.hasMouseMonitors, "v2 idle pet follows the mouse")
    }

    petView.removeFromSuperview()
    XCTAssertFalse(petView.isAnimating)
    XCTAssertFalse(petView.hasMouseMonitors)

    window.contentView?.addSubview(petView)
    XCTAssertTrue(petView.isAnimating)
    petView.setAnimationsActive(false)
    XCTAssertFalse(petView.isAnimating)
    XCTAssertFalse(petView.hasMouseMonitors)
    petView.removeFromSuperview()
  }

  func testVectorPetHasNoTimerAndInputNeededDisablesGaze() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let petView = PetView(frame: NSRect(x: 0, y: 0, width: 78, height: 78))
    window.contentView?.addSubview(petView)
    petView.update(with: .preview(status: .ready))
    XCTAssertFalse(petView.isAnimating, "vector fallback has no sprite timeline")
    XCTAssertFalse(petView.hasMouseMonitors)

    let directory = try PetPackageFixture.writePackage(
      into: try PetPackageFixture.temporaryDirectory(), id: "gaze", version: 2)
    defer { try? FileManager.default.removeItem(at: directory) }
    petView.setSpritePackage(try PetSpritePackageLoader().load(packageDirectory: directory))
    petView.update(with: .preview(status: .inputNeeded))
    XCTAssertTrue(petView.isAnimating)
    XCTAssertFalse(petView.hasMouseMonitors, "waiting state never follows the mouse")
    petView.removeFromSuperview()
  }
}
