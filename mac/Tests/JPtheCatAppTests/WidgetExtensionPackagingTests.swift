import AppKit
import XCTest

final class WidgetExtensionPackagingTests: XCTestCase {
	func testWidgetExtensionIsDeclaredAsAWidgetKitExtension() throws {
		let plist = macRoot()
			.appendingPathComponent("JPtheCatWidgetExtension-Info.plist")
		let data = try Data(contentsOf: plist)
		let value = try XCTUnwrap(
			PropertyListSerialization.propertyList(from: data, options: [], format: nil)
				as? [String: Any])
		let extensionInfo = try XCTUnwrap(value["NSExtension"] as? [String: Any])

		XCTAssertEqual(
			extensionInfo["NSExtensionPointIdentifier"] as? String,
			"com.apple.widgetkit-extension")
		XCTAssertEqual(value["CFBundlePackageType"] as? String, "XPC!")
		XCTAssertEqual(value["CFBundleIdentifier"] as? String, "com.8bittts.jpthecat.widget")
		XCTAssertEqual(value["CFBundleSupportedPlatforms"] as? [String], ["MacOSX"])
		XCTAssertEqual(value["CFBundleIconFile"] as? String, "AppIcon")
	}

	func testWidgetAppGroupUsesMacDeveloperIDFriendlyTeamPrefix() throws {
		let appEntitlements = try String(
			contentsOf: macRoot().appendingPathComponent("JPtheCat.entitlements"),
			encoding: .utf8)
		let widgetEntitlements = try String(
			contentsOf: macRoot().appendingPathComponent("JPtheCatWidgetExtension.entitlements"),
			encoding: .utf8)

		for entitlements in [appEntitlements, widgetEntitlements] {
			XCTAssertTrue(entitlements.contains("GRNGR33Z8A.com.8bittts.jpthecat"))
			XCTAssertFalse(entitlements.contains("group.com.8bittts.jpthecat"))
		}
	}

	func testReleaseScriptsEmbedWidgetExtensionInsidePlugIns() throws {
		let buildScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/build-dmg.sh"),
			encoding: .utf8)
		let localScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/build_and_run.sh"),
			encoding: .utf8)
		let smokeScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/smoke-test.sh"),
			encoding: .utf8)

		for script in [buildScript, localScript] {
			XCTAssertTrue(script.contains("JPtheCatWidgetExtension.appex") || script.contains("${WIDGET_NAME}.appex"))
			XCTAssertTrue(script.contains("Contents/PlugIns") || script.contains("PlugIns"))
			XCTAssertTrue(script.contains("JPtheCatWidgetExtension-Info.plist") || script.contains("WIDGET_SOURCE_PLIST"))
		}
		XCTAssertTrue(smokeScript.contains("com.apple.widgetkit-extension"))
		XCTAssertTrue(smokeScript.contains("JPtheCatWidgetExtension.appex") || smokeScript.contains("${WIDGET_NAME}.appex"))
		XCTAssertTrue(smokeScript.contains("Metadata.appintents"))
		XCTAssertTrue(smokeScript.contains("JPtheCatWidgetConfigurationIntent"))
		XCTAssertTrue(buildScript.contains("stage-widget-appintents-metadata.sh release"))
		XCTAssertTrue(localScript.contains("stage-widget-appintents-metadata.sh \"$CONFIG\""))
		XCTAssertTrue(buildScript.contains("WIDGET_RESOURCES_DIR/AppIcon.icns"))
		XCTAssertTrue(localScript.contains("Contents/Resources/AppIcon.icns"))
	}

	func testWidgetSourceUsesAppleConfigurationPatterns() throws {
		let source = try widgetSource()

		XCTAssertTrue(source.contains("AppIntentConfiguration"))
		XCTAssertFalse(source.contains("StaticConfiguration"))
		XCTAssertTrue(source.contains("import AppIntents"))
		XCTAssertTrue(source.contains("JPtheCatWidgetConfigurationIntent"))
		XCTAssertTrue(source.contains("WidgetConfigurationIntent"))
		XCTAssertTrue(source.contains("JPWidgetProviderChoice"))
		XCTAssertTrue(source.contains("case grok"))
		XCTAssertTrue(source.contains("case museSpark"))
		XCTAssertTrue(source.contains("case copilot"))
		XCTAssertTrue(source.contains("case cursor"))
		XCTAssertTrue(source.contains("@Parameter(title: \"View\", default: .all)"))
		XCTAssertTrue(source.contains("@Parameter(title: \"Show limits\", default: true)"))
		XCTAssertTrue(source.contains("JPWidgetTimeframeChoice"))
		XCTAssertTrue(source.contains("@Parameter(title: \"Timeframe\", default: .fourteenDays)"))
		XCTAssertTrue(source.contains(".supportedFamilies([.systemSmall, .systemMedium, .systemLarge])"))
		XCTAssertTrue(source.contains(".configurationDisplayName(\"JP the Cat\")"))
		XCTAssertTrue(source.contains("containerBackground"))
		XCTAssertTrue(source.contains("@Environment(\\.widgetFamily)"))
	}

	func testAppIntentsMetadataExtractionIsPartOfReleasePackaging() throws {
		let helper = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/stage-widget-appintents-metadata.sh"),
			encoding: .utf8)

		XCTAssertTrue(helper.contains("appintentsmetadataprocessor"))
		XCTAssertTrue(helper.contains("emit-const-values-path"))
		XCTAssertTrue(helper.contains("const-gather-protocols-file"))
		XCTAssertTrue(helper.contains("Metadata.appintents"))
		XCTAssertTrue(helper.contains("JPtheCatWidgetConfigurationIntent"))
		XCTAssertTrue(helper.contains("extract.actionsdata"))
	}

	// The App Group entitlement is load-bearing (the sandboxed widget reads the shared snapshot through
	// it). Signing must fail closed if the entitlements go missing and must assert the group actually
	// landed, since `codesign --verify` never checks entitlement content.
	func testReleaseSigningFailsClosedAndVerifiesAppGroupEntitlement() throws {
		let buildScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/build-dmg.sh"),
			encoding: .utf8)

		XCTAssertTrue(buildScript.contains("verify_app_group_entitlement"))
		XCTAssertTrue(buildScript.contains("GRNGR33Z8A.com.8bittts.jpthecat"))
		XCTAssertTrue(buildScript.contains("refusing to sign the widget without its App Group entitlement"))
	}

	func testConfigurableWidgetTargetLinksAppIntentsFramework() throws {
		let package = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/Package.swift"),
			encoding: .utf8)
		let widgetTargetStart = try XCTUnwrap(package.range(of: "name: \"JPtheCatWidgetExtension\""))
		let suffix = package[widgetTargetStart.lowerBound...]
		let widgetTargetEnd = suffix.range(of: ".testTarget(")?.lowerBound ?? suffix.endIndex
		let widgetTarget = String(suffix[..<widgetTargetEnd])

		XCTAssertTrue(widgetTarget.contains(".linkedFramework(\"AppIntents\")"))
		XCTAssertTrue(widgetTarget.contains(".linkedFramework(\"WidgetKit\")"))
	}

	// The widget MUST link with the legacy `_NSExtensionMain` entry point. Without it, SwiftPM's
	// synthesized `@main` boots through ExtensionFoundation and traps ("Unrecognized extension type"),
	// so the extension never launches and never appears in the macOS widget gallery. Guard the flag so
	// this can't silently regress.
	func testWidgetForcesNSExtensionMainEntryPoint() throws {
		let package = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/Package.swift"),
			encoding: .utf8)
		let widgetTargetStart = try XCTUnwrap(package.range(of: "name: \"JPtheCatWidgetExtension\""))
		let suffix = package[widgetTargetStart.lowerBound...]
		let widgetTargetEnd = suffix.range(of: ".testTarget(")?.lowerBound ?? suffix.endIndex
		let widgetTarget = String(suffix[..<widgetTargetEnd])

		XCTAssertTrue(widgetTarget.contains("_NSExtensionMain"))
	}

	// The widget target must SHIP the brand marks (JP header + per-provider) and they must decode. The
	// header mark was blank because the SVG/PNG marks either weren't bundled (provider marks) or were
	// loaded with the name-based `Image(name:bundle:)` that can't resolve a loose macOS resource.
	func testWidgetBundlesBrandMarksThatDecode() throws {
		let resources = macRoot()
			.appendingPathComponent("Sources/JPtheCatWidgetExtension/Resources")
		for asset in [
			"jp-menubar.png", "provider-claude.svg", "provider-codex.svg", "provider-grok.svg",
			"provider-muse_spark.svg", "provider-copilot.svg", "provider-cursor.svg",
		] {
			let url = resources.appendingPathComponent(asset)
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: url.path),
				"widget target is missing bundled mark \(asset)")
			let image = NSImage(contentsOf: url)
			XCTAssertNotNil(image, "\(asset) did not decode to an NSImage")
			XCTAssertGreaterThan(image?.size.width ?? 0, 0, "\(asset) decoded to a zero-size image")
		}
	}

	// The All-providers faces list every contributing dashboard row, so the widget must carry every
	// provider mark the app ships. OpenCode Zen and Go once rendered as bare dots on placed widgets
	// because only the app bundled their marks.
	func testWidgetCarriesEveryProviderMarkTheAppShips() throws {
		let appResources = macRoot().appendingPathComponent("Sources/JPtheCatApp/Resources")
		let widgetResources = macRoot().appendingPathComponent("Sources/JPtheCatWidgetExtension/Resources")
		let marks = try FileManager.default.contentsOfDirectory(atPath: appResources.path)
			.filter { $0.hasPrefix("provider-") && $0.hasSuffix(".svg") }
		XCTAssertTrue(marks.contains("provider-opencode.svg"), "app marks: \(marks)")
		XCTAssertTrue(marks.contains("provider-opencodego.svg"), "app marks: \(marks)")
		for mark in marks {
			let widgetMark = widgetResources.appendingPathComponent(mark)
			XCTAssertEqual(
				FileManager.default.contents(atPath: widgetMark.path),
				FileManager.default.contents(atPath: appResources.appendingPathComponent(mark).path),
				"widget copy of \(mark) is missing or differs from the app's")
		}
	}

	// Guard the exact blank-mark regression: the widget must load marks via NSImage (the app's path),
	// never via SwiftUI's `Image("name", bundle:)`, which does not resolve loose PNGs on macOS.
	func testWidgetLoadsMarksViaNSImageNotNamedImageInitializer() throws {
		let source = try widgetSource()

		XCTAssertTrue(source.contains("image(forResource:"))
		XCTAssertTrue(source.contains("NSImage(contentsOf:"))
		XCTAssertTrue(source.contains("ProviderMarkChip"))
		XCTAssertFalse(
			source.contains("Image(\"jp-menubar\""),
			"widget must not use the name-based Image initializer that rendered the mark blank")
	}

	// Rule (b): every widget family (including systemSmall, which has no provider rows) must disclose the
	// notional basis when the aggregate total includes Codex list-price, and must not resurrect the
	// inverted helper / "basis noted by provider" fallback that hid it exactly when Codex was included.
	func testLegacyGrokBotWidgetChoiceResolvesToUnifiedGrok() throws {
		let source = try String(
			contentsOf: macRoot().appendingPathComponent("Sources/JPtheCatWidgetExtension/WidgetConfiguration.swift"),
			encoding: .utf8)
		XCTAssertTrue(source.contains("case grokBot"))
		XCTAssertTrue(source.contains("case .cursor, .grokBot: return \"grok\""))
	}

	func testWidgetDisclosesNotionalBasisOnTheAggregate() throws {
		let source = try widgetSource()

		XCTAssertTrue(source.contains("disclosesNotionalBasis"))
		XCTAssertTrue(source.contains("ProviderBasisBadge"))
		XCTAssertFalse(source.contains("basis != .realAndNotionalListPrice"))
		XCTAssertFalse(source.contains("basis noted by provider"))
	}

	private func repoRoot() -> URL {
		macRoot().deletingLastPathComponent()
	}

	// The widget extension's source is split across several files by concern (JPtheCatWidget.swift,
	// WidgetConfiguration.swift, WidgetComponents.swift, WidgetSupport.swift). These source-text guards
	// assert against the target as a whole, so concatenate every `.swift` in the target directory rather
	// than pinning one filename — a future re-split can't silently defeat the guard.
	private func widgetSource() throws -> String {
		let dir = repoRoot().appendingPathComponent("mac/Sources/JPtheCatWidgetExtension")
		let files = try FileManager.default
			.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "swift" }
		XCTAssertFalse(files.isEmpty, "no widget-extension Swift sources found at \(dir.path)")
		return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
	}

	private func macRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
