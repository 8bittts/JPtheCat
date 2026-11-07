import AppKit
import XCTest

@testable import JPtheCatApp

/// Builds the real `NSMenu` — a source-string match would stay green if the Help item existed only
/// in a comment (the previous `MainMenu.swift` header claimed Help while the menu omitted it).
final class MainMenuTests: XCTestCase {
	@MainActor
	func testHelpMenuIsLastAndWiredToTheSite() throws {
		let owner = AppDelegate()
		let menu = MainMenu.build(owner: owner, includeUpdates: false)

		XCTAssertEqual(menu.items.last?.submenu?.title, "Help")
		let helpMenu = try XCTUnwrap(menu.items.last?.submenu)
		XCTAssertTrue(helpMenu === NSApplication.shared.helpMenu)

		XCTAssertEqual(helpMenu.items.count, 1)
		let help = try XCTUnwrap(helpMenu.items.first)
		XCTAssertEqual(help.title, "JP the Cat Help")
		XCTAssertEqual(help.keyEquivalent, "?")
		XCTAssertEqual(help.action, #selector(AppDelegate.openHelpFromMenu))
		XCTAssertTrue(help.target as AnyObject? === owner)
	}

	@MainActor
	func testWindowMenuClosesWithCommandWBeforeMinimize() throws {
		let menu = MainMenu.build(owner: AppDelegate(), includeUpdates: true)
		let windowMenu = try XCTUnwrap(menu.items.first { $0.submenu?.title == "Window" }?.submenu)
		XCTAssertTrue(windowMenu === NSApplication.shared.windowsMenu)

		let titles = windowMenu.items.map(\.title)
		let closeIndex = try XCTUnwrap(titles.firstIndex(of: "Close"))
		let minimizeIndex = try XCTUnwrap(titles.firstIndex(of: "Minimize"))
		XCTAssertLessThan(closeIndex, minimizeIndex)

		let close = windowMenu.items[closeIndex]
		XCTAssertEqual(close.keyEquivalent, "w")
		XCTAssertEqual(close.action, #selector(NSWindow.performClose(_:)))
	}

	@MainActor
	func testHelpStaysLastWhetherUpdatesArePresent() throws {
		for includeUpdates in [false, true] {
			let menu = MainMenu.build(owner: AppDelegate(), includeUpdates: includeUpdates)
			XCTAssertEqual(
				menu.items.last?.submenu?.title, "Help",
				"Help must remain the last menu when includeUpdates=\(includeUpdates)")
			let appMenu = try XCTUnwrap(menu.items.first?.submenu)
			let settings = try XCTUnwrap(appMenu.items.first { $0.title == "Settings…" })
			XCTAssertEqual(settings.keyEquivalent, ",")
			XCTAssertEqual(settings.action, #selector(AppDelegate.openSettingsFromMenu))
		}
	}
}
