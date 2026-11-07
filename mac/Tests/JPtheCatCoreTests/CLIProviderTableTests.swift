import Foundation
import XCTest

@testable import JPtheCatCore

/// Guards `jpthecat-cli`'s single `cliProviders` table.
///
/// [Why this exists] The CLI used to spell the same ordered provider list FIVE times (a name ternary,
/// an id ternary, a construction ladder, a "no source found" directory ternary and an
/// `indexer.refresh` ternary), plus a per-provider case in `selectedAutomationProviders` and a 30-line
/// downcast switch whose `guard let … as? XProvider else { return }` arms turned a mismatch into a
/// SILENT no-op. Adding a provider meant eight coordinated edits with nothing checking they agreed.
/// The table is now the one source; this guard proves it covers exactly the providers the CLI claims
/// to expose, and that `--provider all` still means `ProviderCatalog.live` and nothing else.
///
/// `main.swift` is an executable target's top-level code and cannot be imported, so this reads its
/// SOURCE — the same technique `ProviderCatalogTests` already uses for the CLI.
final class CLIProviderTableTests: XCTestCase {
	private struct TableRow {
		let id: String
		let flag: String
		let selectionTokens: [String]
		let includedInAll: Bool
	}

	private func cliSource() throws -> String {
		let packageRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatCoreTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
		return try String(
			contentsOf: packageRoot.appendingPathComponent("Sources/jpthecat-cli/main.swift"),
			encoding: .utf8)
	}

	/// The literal table text: the default row plus the array, which is where every `id:` lives.
	private func tableText(_ source: String) throws -> String {
		let start = try XCTUnwrap(
			source.range(of: "static let claude = CLIProvider("),
			"the CLI provider table was renamed — update this guard rather than dropping it")
		let end = try XCTUnwrap(
			source.range(of: "\n\t]\n", range: start.upperBound..<source.endIndex),
			"could not find the end of the `CLIProviderTable.all` array literal")
		return String(source[start.lowerBound..<end.upperBound])
	}

	private func captures(_ pattern: String, in text: String) throws -> [String] {
		let regex = try NSRegularExpression(pattern: pattern)
		let full = NSRange(text.startIndex..<text.endIndex, in: text)
		return regex.matches(in: text, range: full).compactMap { match in
			Range(match.range(at: 1), in: text).map { String(text[$0]) }
		}
	}

	private func parsedTable() throws -> [TableRow] {
		let text = try tableText(try cliSource())
		let ids = try captures(#"\bid: \.(\w+)"#, in: text)
		let flags = try captures(#"\bflag: "(--[a-z-]+)""#, in: text)
		let tokenLists = try captures(#"\bselectionTokens: \[([^\]]+)\]"#, in: text)
		let inAll = try captures(#"\bincludedInAll: (true|false)"#, in: text)
		XCTAssertEqual(ids.count, flags.count, "every row needs a flag")
		XCTAssertEqual(ids.count, tokenLists.count, "every row needs selection tokens")
		XCTAssertEqual(ids.count, inAll.count, "every row needs an `includedInAll` decision")
		guard ids.count == flags.count, ids.count == tokenLists.count, ids.count == inAll.count else {
			return []
		}
		var rows: [TableRow] = []
		for index in ids.indices {
			rows.append(
				TableRow(
					id: ids[index],
					flag: flags[index],
					selectionTokens: try captures(#""([a-z_-]+)""#, in: tokenLists[index]),
					includedInAll: inAll[index] == "true"))
		}
		return rows
	}

	/// The exact provider set the CLI exposes. A new provider must land here in the same change, so a
	/// half-wired addition fails loudly instead of silently contributing nothing.
	func testTableCoversExactlyTheProvidersTheCLIExposes() throws {
		let expected: [(id: String, flag: String, tokens: [String], inAll: Bool)] = [
			("claude", "--claude", ["claude"], true),
			("codex", "--codex", ["codex"], true),
			("grok", "--grok", ["grok", "cursor", "grok-bot", "grok_bot", "grokbot"], true),
			("museSpark", "--muse-spark", ["muse-spark", "muse_spark", "musespark"], true),
			("gemini", "--gemini", ["gemini"], false),
			("opencode", "--opencode", ["opencode", "opencode-zen", "opencode_zen", "zen"], true),
			("opencodego", "--opencode-go", ["opencode-go", "opencode_go", "opencodego"], true),
			("copilot", "--copilot", ["copilot"], false),
			("nemotron", "--nemotron", ["nemotron"], true),
			("mimo", "--mimo", ["mimo"], true),
			("bigPickle", "--big-pickle", ["big-pickle", "big_pickle", "bigpickle"], true),
			("deepseek", "--deepseek", ["deepseek"], true),
		]
		let table = try parsedTable()
		XCTAssertEqual(table.map(\.id), expected.map(\.id))
		XCTAssertEqual(table.map(\.flag), expected.map(\.flag))
		XCTAssertEqual(table.map(\.selectionTokens), expected.map(\.tokens))
		XCTAssertEqual(table.map(\.includedInAll), expected.map(\.inAll))

		// Every id must be a real `ProviderID` case, not a typo the compiler happens to accept
		// somewhere else in the file.
		let known = Set(ProviderID.allCases.map { String(describing: $0) })
		for row in table {
			XCTAssertTrue(known.contains(row.id), "`\(row.id)` is not a ProviderID case")
		}
	}

	/// `--provider all` is every row the dashboard sums (`ProviderCatalog.aggregateIDs`: the live set
	/// plus the OpenCode model-brand rows JP accounts for locally) plus the two gateways, which the
	/// snapshot lists but keeps out of its total. Promoting a provider in `ProviderCatalog` or
	/// `OpenCodeBrand` without flipping `includedInAll` (or the reverse) would silently drift the
	/// CLI's aggregate away from the app's — which is exactly what happened when the brand rows were
	/// summed on the dashboard but excluded here.
	func testProviderAllMatchesTheDashboardAggregateSetExactly() throws {
		let inAll = Set(try parsedTable().filter(\.includedInAll).map(\.id))
		let expected = Set(ProviderCatalog.aggregateIDs.map { String(describing: $0) })
			.union(ProviderID.allCases.filter { ProviderBasis.of($0) == .gateway }.map { String(describing: $0) })
		XCTAssertEqual(inAll, expected)
		XCTAssertEqual(
			Set(ProviderCatalog.live.map { String(describing: $0.id) }),
			["claude", "codex", "grok", "museSpark", "opencode", "opencodego"])
		XCTAssertEqual(
			Set(ProviderCatalog.localAccountingIDs.map { String(describing: $0) }),
			["nemotron", "mimo", "bigPickle", "deepseek"])
	}

	/// The help text is the CLI's contract; the table is its implementation. They must agree.
	func testHelpTextListsExactlyTheTableRows() throws {
		let source = try cliSource()
		let table = try parsedTable()

		let legacyUsage = "jpthecat-cli [" + table.map(\.flag).joined(separator: " | ") + "]"
		XCTAssertTrue(
			source.contains(legacyUsage),
			"the legacy usage line must list exactly the table's flags, in order: \(legacyUsage)")

		let providerTokens = "all|" + table.compactMap(\.selectionTokens.first).joined(separator: "|")
		XCTAssertEqual(
			source.components(separatedBy: "--provider \(providerTokens)").count - 1, 2,
			"both the snapshot and report usage lines must list exactly the table's canonical tokens")

		for row in table {
			XCTAssertTrue(
				source.contains("  \(row.flag) "),
				"`\(row.flag)` is in the table but has no help entry")
		}
	}

	/// [CRITICAL] The table must stay a lazily-initialized `static let` on a type.
	///
	/// Top-level globals in `main.swift` initialize in STATEMENT ORDER at runtime, and the
	/// `snapshot`/`report` dispatch runs near the top of the file — long before a table declared
	/// further down would exist. As a top-level `let`, `selectedAutomationProviders` read
	/// uninitialized memory and every `snapshot`/`report` invocation segfaulted (exit 139) while
	/// `--help` and the legacy flag path stayed perfectly healthy.
	func testTableIsLazilyInitializedNotATopLevelGlobal() throws {
		let source = try cliSource()
		XCTAssertTrue(source.contains("enum CLIProviderTable {"))
		XCTAssertTrue(source.contains("\tstatic let all: [CLIProvider] = ["))
		XCTAssertFalse(
			source.contains("\nlet cliProviders"),
			"a top-level table global reintroduces the initialization-order segfault")
	}

	/// The downcast switch is gone for good: it no-oped in silence on a mismatch, and its `default:`
	/// arm became unreachable once every row was typed `IndexableProvider`.
	func testIndexedRefreshHasNoDowncastSwitch() throws {
		let source = try cliSource()
		XCTAssertTrue(source.contains("-> [any IndexableProvider]"))
		XCTAssertTrue(source.contains("let make: @Sendable (URL?) -> any IndexableProvider"))
		XCTAssertTrue(source.contains("_ = try indexer.refresh(provider)"))
		for provider in [
			"ClaudeProvider", "CodexProvider", "GrokProvider", "MuseSparkProvider", "GeminiProvider",
			"OpenCodeProvider", "OpenCodeGoProvider", "CopilotProvider", "CursorProvider",
		] {
			XCTAssertFalse(
				source.contains("as? \(provider)"),
				"a downcast to \(provider) came back — a mismatch there is a silent no-op")
		}
	}
}
