// swift-tools-version:6.0
import PackageDescription

// JPtheCat — macOS menu-bar AI token-cost meter.
let package = Package(
	name: "JPtheCat",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "JPtheCat", targets: ["JPtheCatApp"]),
		.executable(name: "JPtheCatWidgetExtension", targets: ["JPtheCatWidgetExtension"]),
		.executable(name: "jpthecat-cli", targets: ["jpthecat-cli"]),
		.library(name: "JPtheCatCore", targets: ["JPtheCatCore"]),
	],
	targets: [
		.target(
			name: "JPtheCatCore",
			resources: [.process("Resources")]
		),
		.executableTarget(
			name: "JPtheCatApp",
			dependencies: ["JPtheCatCore"],
			resources: [.process("Resources")],
			swiftSettings: [
				// Sparkle.framework is vendored (not a SwiftPM dep) under mac/tools/sparkle.
				.unsafeFlags(["-F", "tools/sparkle"]),
			],
			linkerSettings: [
				.unsafeFlags([
					"-F", "tools/sparkle",
					"-framework", "Sparkle",
					// Production: framework lives in the .app's Contents/Frameworks.
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
					// Dev (`swift run`/staged from .build): mac/.build/debug/JPtheCat → ../../tools/sparkle
					// (JPtheCat's .build is under mac/, so 2 ups — NOT dockishOS's 3).
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../tools/sparkle",
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../tools/sparkle",
					// Tests: .build/<triple>/debug/JPtheCatPackageTests.xctest/Contents/MacOS.
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../../../../tools/sparkle",
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../tools/sparkle",
				]),
			]
		),
		.executableTarget(
			name: "jpthecat-cli",
			dependencies: ["JPtheCatCore"]
		),
		.executableTarget(
			name: "JPtheCatWidgetExtension",
			dependencies: ["JPtheCatCore"],
			resources: [.process("Resources")],
			swiftSettings: [
				.unsafeFlags(["-application-extension"]),
			],
			linkerSettings: [
				.linkedFramework("AppIntents"),
				.linkedFramework("SwiftUI"),
				.linkedFramework("WidgetKit"),
				// SwiftPM's synthesized `@main` entry boots through ExtensionFoundation, which traps with
				// "Unrecognized extension type" for a widget — the extension never launches, so it never
				// appears in the macOS widget gallery. Force the legacy PlugInKit XPC entry point
				// `_NSExtensionMain` (the path Xcode-built widgets use) so chronod can host the extension.
				// Verify with a direct run: it must print "An XPC Service cannot be run directly", not trap.
				.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
			]
		),
		.testTarget(
			name: "JPtheCatCoreTests",
			dependencies: ["JPtheCatCore"],
			resources: [.process("Fixtures")]
		),
		.testTarget(
			name: "JPtheCatAppTests",
			dependencies: ["JPtheCatApp"],
			swiftSettings: [
				// `@testable import JPtheCatApp` pulls in its `import Sparkle`, so the test target needs the
				// vendored framework's search path too (tools-version 6.0 no longer inherits the app
				// target's unsafeFlags). Mirrors JPtheCatApp's `-F tools/sparkle`.
				.unsafeFlags(["-F", "tools/sparkle"]),
			],
			linkerSettings: [
				.unsafeFlags([
					"-F", "tools/sparkle",
					"-framework", "Sparkle",
					// The test bundle sits at `<scratch>/<layout>/JPtheCatAppTests.xctest/Contents/MacOS/`,
					// so how many `../` reach `mac/` depends on the build system's product layout — six
					// for the legacy `native` layout (`.build/arm64-apple-macosx/debug`) and seven for
					// the current default `swiftbuild` layout (`.build/out/Products/Debug`). Both are
					// listed: an rpath that resolves to nothing is inert, while a missing one fails
					// `dlopen` with "Library not loaded: @rpath/Sparkle.framework/…" and takes the whole
					// `swift test` gate down with it.
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../../../../tools/sparkle",
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../tools/sparkle",
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../../../../../tools/sparkle",
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../../tools/sparkle",
				]),
			]
		),
		.testTarget(
			name: "JPtheCatWidgetExtensionTests",
			dependencies: ["JPtheCatWidgetExtension", "JPtheCatCore"]
		),
	],
	// Full Swift 6 language mode (strict concurrency) across every target — future-proofs against
	// Swift 7's default. Migration detail: _docs/00-foundation.md#swift-6-language-mode.
	swiftLanguageModes: [.v6]
)
