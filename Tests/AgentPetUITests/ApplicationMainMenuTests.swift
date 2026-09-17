import AppKit
import XCTest

@testable import AgentPetUI

@MainActor
final class ApplicationMainMenuTests: XCTestCase {
  private final class Target: NSObject {
    var openCount = 0
    @objc func openSettings() { openCount += 1 }
  }

  func testMenuRoutesSettingsEditingAndCloseShortcuts() {
    let target = Target()
    let menu = ApplicationMainMenu.make(
      settingsTarget: target, settingsAction: #selector(Target.openSettings))

    let items = menu.items.compactMap(\.submenu).flatMap(\.items)
    func item(_ key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem? {
      items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers }
    }

    XCTAssertEqual(menu.items.map { $0.submenu?.title }, ["Oh My Agent Pet", "Edit", "Window"])
    XCTAssertEqual(item(",")?.action, #selector(Target.openSettings))
    XCTAssertTrue(item(",")?.target === target)
    XCTAssertEqual(item("v")?.action, #selector(NSText.paste(_:)))
    XCTAssertNil(item("v")?.target, "editing actions go to the first responder")
    XCTAssertEqual(item("c")?.action, #selector(NSText.copy(_:)))
    XCTAssertEqual(item("x")?.action, #selector(NSText.cut(_:)))
    XCTAssertEqual(item("a")?.action, #selector(NSText.selectAll(_:)))
    XCTAssertEqual(item("w")?.action, #selector(NSWindow.performClose(_:)))
    XCTAssertEqual(item("q")?.action, #selector(NSApplication.terminate(_:)))
    XCTAssertNotNil(item("z", modifiers: [.command, .shift]), "redo keeps its shift modifier")
  }

  func testCommandCommaKeyEventReachesSettingsTarget() {
    // Menu actions are delivered through the shared application, which xctest creates lazily.
    _ = NSApplication.shared
    let target = Target()
    let menu = ApplicationMainMenu.make(
      settingsTarget: target, settingsAction: #selector(Target.openSettings))
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
      context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false,
      keyCode: 43)!

    XCTAssertTrue(menu.performKeyEquivalent(with: event))
    // AppKit delivers the menu action after the run loop turns, not synchronously.
    let deadline = Date().addingTimeInterval(2)
    while target.openCount == 0, Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertEqual(target.openCount, 1)
  }
}
