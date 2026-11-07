import AppKit

/// The standard macOS menu-bar menu (the row of menus at the top of the screen while JPtheCat is
/// frontmost). JPtheCat is Dock-visible (`.regular`), so it must present a normal app menu — the
/// bold app menu named "JP the Cat" with About/Settings/Services/Hide/Quit, plus Edit, Window, and
/// Help — exactly like a conventional Mac app. Help is last and assigned to `NSApplication.shared.helpMenu` so
/// Spotlight-for-Help can search menu items. This is distinct from the compact right-click
/// status-item menu (`StatusBarController`), which stays intentionally minimal and money-free.
///
/// Custom rows (Check for Updates…, Settings…) target `owner`; standard rows ride the responder
/// chain with `target: nil` so AppKit supplies About/Hide/Services/Quit/Edit/Window automatically.
enum MainMenu {
  /// The human-readable app name shown in the bold application menu. Kept in sync with the localized
  /// `CFBundleDisplayName` in `en.lproj/InfoPlist.strings`. The product/bundle identifiers stay
  /// `JPtheCat`; only the display reads "JP the Cat".
  static let appName = "JP the Cat"

  @MainActor
  static func build(owner: AppDelegate, includeUpdates: Bool) -> NSMenu {
    let mainMenu = NSMenu()

    // MARK: App menu (bold, first)
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu

    appMenu.addItem(
      withTitle: "About \(appName)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: "")

    if includeUpdates {
      appMenu.addItem(.separator())
      let updates = NSMenuItem(
        title: "Check for Updates…",
        action: #selector(AppDelegate.checkForUpdatesFromMenu),
        keyEquivalent: "")
      updates.target = owner
      appMenu.addItem(updates)
    }

    appMenu.addItem(.separator())
    let settings = NSMenuItem(
      title: "Settings…", action: #selector(AppDelegate.openSettingsFromMenu), keyEquivalent: ",")
    settings.target = owner
    appMenu.addItem(settings)

    appMenu.addItem(.separator())
    let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    services.submenu = servicesMenu
    appMenu.addItem(services)
    NSApplication.shared.servicesMenu = servicesMenu

    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(
      withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")

    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    // MARK: Edit menu (so text fields get standard Undo/Cut/Copy/Paste/Select All)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    // MARK: Window menu
    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenuItem.submenu = windowMenu
    windowMenu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowMenu.addItem(
      withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(
      withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowMenu.addItem(.separator())
    windowMenu.addItem(
      withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
      keyEquivalent: "")
    NSApplication.shared.windowsMenu = windowMenu

    // MARK: Help menu (last)
    let helpMenuItem = NSMenuItem()
    mainMenu.addItem(helpMenuItem)
    let helpMenu = NSMenu(title: "Help")
    helpMenuItem.submenu = helpMenu
    let help = NSMenuItem(
      title: "\(appName) Help",
      action: #selector(AppDelegate.openHelpFromMenu),
      keyEquivalent: "?")
    help.target = owner
    helpMenu.addItem(help)
    NSApplication.shared.helpMenu = helpMenu

    return mainMenu
  }
}
