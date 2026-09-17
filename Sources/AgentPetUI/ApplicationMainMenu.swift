import AppKit

// An `LSUIElement` app shows no menu bar, but AppKit still routes Command shortcuts such as
// Cmd-V in text fields, Cmd-W and Cmd-, through `NSApp.mainMenu`. This builds the minimum menu
// that makes those shortcuts work in the settings window.
public enum ApplicationMainMenu {
  public static let settingsKeyEquivalent = ","

  public static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
    let mainMenu = NSMenu()

    let applicationMenu = NSMenu(title: "Oh My Agent Pet")
    let settings = NSMenuItem(
      title: "Settings…", action: settingsAction, keyEquivalent: settingsKeyEquivalent)
    settings.target = settingsTarget
    applicationMenu.addItem(settings)
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      NSMenuItem(
        title: "Quit Oh My Agent Pet",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )
    mainMenu.addItem(submenu(applicationMenu))

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(.separator())
    editMenu.addItem(
      NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(
      NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(
      NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(
      NSMenuItem(
        title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    mainMenu.addItem(submenu(editMenu))

    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      NSMenuItem(
        title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    mainMenu.addItem(submenu(windowMenu))
    return mainMenu
  }

  private static func submenu(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }
}
