import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
  static let lastPaneKey = "settings.lastPane"

  public let model: SettingsModel
  private let defaults: UserDefaults
  private var window: NSWindow?
  private(set) var hostingController: NSHostingController<SettingsRootView>?

  public convenience init(model: SettingsModel) {
    self.init(model: model, defaults: .standard)
  }

  init(model: SettingsModel, defaults: UserDefaults) {
    self.model = model
    self.defaults = defaults
    super.init()
    model.showPane(Self.storedPane(in: defaults))
  }

  public var isWindowVisible: Bool { window?.isVisible ?? false }

  // Menu, Command-Comma and app reopen all come here. An existing window is brought to the front
  // instead of creating a second one; a closed window is rebuilt from the stored pane.
  public func show(pane: SettingsPane? = nil) {
    if let pane { model.showPane(pane) }
    let window = self.window ?? makeWindow()
    self.window = window
    (window.toolbar as? SettingsToolbar)?.selectedItemIdentifier = NSToolbarItem.Identifier(
      model.pane.rawValue)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  public func windowWillClose(_ notification: Notification) {
    defaults.set(model.pane.rawValue, forKey: Self.lastPaneKey)
    window?.contentViewController = nil
    hostingController = nil
    window?.delegate = nil
    window?.toolbar = nil
    window = nil
    model.petLibrary.windowDidClose()
  }

  public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    SettingsPane.available.map { NSToolbarItem.Identifier($0.rawValue) }
  }

  public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  public func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard let pane = SettingsPane(rawValue: itemIdentifier.rawValue) else { return nil }
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = pane.title
    item.paletteLabel = pane.title
    item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
    item.target = self
    item.action = #selector(selectPane(_:))
    return item
  }

  @objc private func selectPane(_ sender: NSToolbarItem) {
    guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
    model.showPane(pane)
    defaults.set(pane.rawValue, forKey: Self.lastPaneKey)
    window?.title = Self.windowTitle(for: pane)
  }

  private func makeWindow() -> NSWindow {
    let hosting = NSHostingController(rootView: SettingsRootView(model: model))
    hostingController = hosting
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: DesignTokens.settingsWindowSize),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hosting
    window.title = Self.windowTitle(for: model.pane)
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .preference
    window.level = .normal
    window.delegate = self
    let toolbar = SettingsToolbar(identifier: "com.seongmin.OhMyAgentPet.settings")
    toolbar.delegate = self
    toolbar.allowsUserCustomization = false
    toolbar.displayMode = .iconAndLabel
    window.toolbar = toolbar
    toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(model.pane.rawValue)
    window.center()
    return window
  }

  private static func storedPane(in defaults: UserDefaults) -> SettingsPane {
    defaults.string(forKey: lastPaneKey).flatMap(SettingsPane.init(rawValue:)) ?? .general
  }

  private static func windowTitle(for pane: SettingsPane) -> String {
    "\(pane.title) — Oh My Agent Pet"
  }
}

@MainActor
private final class SettingsToolbar: NSToolbar {}
