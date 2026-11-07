import Foundation
import XCTest

/// Shared source-text scanner for every guard test that asserts on `Sources/JPtheCatApp` TEXT.
///
/// [CRITICAL] A guard that reads one source file by LITERAL PATH freezes that file's size forever.
/// Extracting a surface out of it either breaks the guard outright or — far worse — makes an
/// `XCTAssertFalse` pass VACUOUSLY, silently deleting the protection the guard encodes. Every
/// source-text guard therefore resolves its text through this scanner, which
///   - resolves the sources directory from `#filePath` (never the process working directory), and
///   - walks EVERY `Sources/JPtheCatApp/**/*.swift` rather than a hardcoded file list, and
///   - THROWS a named error when an anchor symbol is missing or ambiguous,
/// so a moved surface fails LOUDLY, naming the anchor it could not find, instead of going green.
///
/// [NOTE] The brace matcher is a heuristic Swift lexer: it skips `//` and nested `/* */` comments
/// and `"` / `"""` string literals before counting braces. It does not model raw strings (`#"…"#`)
/// — the app sources contain none, and adding one inside a scanned declaration would show up as a
/// loud slice mismatch, never as a silent pass.
enum AppSourceScanner {
	struct SourceFile: Sendable {
		/// Path relative to `Sources/JPtheCatApp`, e.g. `DashboardView.swift`.
		let name: String
		let text: String
	}

	/// `CustomStringConvertible` matters here: XCTest prints a caught error with `String(describing:)`,
	/// so without it the failure reads as struct reflection instead of the actionable sentence.
	struct ScanError: LocalizedError, CustomStringConvertible {
		let message: String
		var errorDescription: String? { message }
		var description: String { message }
	}

	// MARK: - Roots

	/// `mac/Tests/JPtheCatAppTests/Support/` -> repo root.
	static var repoRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // Support
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.deletingLastPathComponent()  // <repo root>
	}

	static var appSourcesRoot: URL {
		repoRoot.appendingPathComponent("mac/Sources/JPtheCatApp")
	}

	// MARK: - The scanned set

	/// Every app source, loaded once. A `static let` is lazy and thread-safe, and the value is
	/// immutable, so the parallel test runner shares it safely.
	private static let loaded: [SourceFile] = {
		let root = appSourcesRoot
		guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
		var out: [SourceFile] = []
		for case let relative as String in walker where relative.hasSuffix(".swift") {
			guard
				let text = try? String(
					contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
			else { continue }
			out.append(SourceFile(name: relative, text: text))
		}
		return out.sorted { $0.name < $1.name }
	}()

	/// The minimum plausible app-source count. A scan that collapses below this is a broken path
	/// resolution, and every `XCTAssertFalse` built on it would pass vacuously — so it throws.
	private static let minimumSourceCount = 20

	static func files() throws -> [SourceFile] {
		let all = loaded
		guard all.count >= minimumSourceCount else {
			throw ScanError(
				message: """
					AppSourceScanner found only \(all.count) sources under \(appSourcesRoot.path) \
					(expected at least \(minimumSourceCount)). Every source-text guard would pass \
					vacuously — fix the path resolution rather than lowering the floor.
					""")
		}
		return all
	}

	/// Every app source concatenated. Use for `contains` guards that assert a string exists (or must
	/// exist NOWHERE) in the app, independent of which file currently hosts it.
	static func joined() throws -> String {
		try files().map(\.text).joined(separator: "\n")
	}

	/// Occurrence count across the WHOLE scanned set — never one file, or a split would silently
	/// halve the count a guard pins.
	static func occurrences(of needle: String) throws -> Int {
		guard !needle.isEmpty else { return 0 }
		return try files().reduce(0) { $0 + $1.text.components(separatedBy: needle).count - 1 }
	}

	/// The single file containing `needle`. Ordering guards need this: relative position is only
	/// meaningful inside one file, so a surface whose ordered parts drift apart must fail loudly.
	static func file(containing needle: String) throws -> SourceFile {
		let hits = try files().filter { $0.text.contains(needle) }
		guard let only = hits.first else {
			throw ScanError(
				message: "no app source contains `\(needle)` — the guarded surface moved or was deleted")
		}
		guard hits.count == 1 else {
			throw ScanError(
				message: """
					`\(needle)` appears in \(hits.count) app sources (\(hits.map(\.name).joined(separator: ", "))). \
					An ordering guard needs exactly one host file — disambiguate the anchor.
					""")
		}
		return only
	}

	/// A source resolved by FILE NAME anywhere under `Sources/JPtheCatApp` (subdirectories included),
	/// for guards about a file that is itself the unit under test rather than a movable surface.
	static func source(named fileName: String) throws -> String {
		let hits = try files().filter { ($0.name as NSString).lastPathComponent == fileName }
		guard let only = hits.first else {
			throw ScanError(message: "no app source named `\(fileName)` — it was renamed or removed")
		}
		guard hits.count == 1 else {
			throw ScanError(
				message: "\(hits.count) app sources are named `\(fileName)`: \(hits.map(\.name).joined(separator: ", "))")
		}
		return only.text
	}

	// MARK: - Declaration slices

	/// The brace-matched body of the declaration introduced by `anchor` (e.g.
	/// `private struct ClaudeLimitsRow` or `private var footer: some View`), found wherever it now
	/// lives. THROWS when the anchor is missing or ambiguous — a slice guard must never degrade into
	/// an assertion over empty text.
	static func body(of anchor: String) throws -> String {
		let all = try files()
		let hits = all.filter { $0.text.contains(anchor) }
		guard let host = hits.first else {
			throw ScanError(
				message: """
					declaration anchor `\(anchor)` was not found in any of the \(all.count) app sources. \
					The guarded declaration was renamed, deleted, or reworded — update the anchor rather \
					than dropping the guard.
					""")
		}
		guard hits.count == 1 else {
			throw ScanError(
				message: """
					declaration anchor `\(anchor)` is ambiguous — it appears in \(hits.count) sources \
					(\(hits.map(\.name).joined(separator: ", "))). Use `member(_:of:)` or a longer anchor.
					""")
		}
		return try body(of: anchor, in: host.text, origin: host.name)
	}

	/// The concatenated bodies of several declarations, for a guard whose original slice deliberately
	/// spanned more than one (each one still resolved, and still required, individually).
	static func bodies(of anchors: [String]) throws -> String {
		var out: [String] = []
		for anchor in anchors { out.append(try body(of: anchor)) }
		return out.joined(separator: "\n")
	}

	/// Every declaration of `typeName` plus every `extension typeName`, concatenated — the type's
	/// whole surface, so moving members into an extension in another file keeps the guard green while
	/// deleting them still fails.
	static func typeSurface(_ typeName: String) throws -> String {
		let escaped = NSRegularExpression.escapedPattern(for: typeName)
		let pattern =
			"(?m)^[ \t]*(?:(?:public|internal|private|fileprivate|final|@MainActor|@objc|nonisolated)[ \t]+)*"
			+ "(?:struct|class|enum|actor|extension)[ \t]+\(escaped)\\b"
		let regex = try NSRegularExpression(pattern: pattern)
		var out: [String] = []
		for source in try files() {
			let text = source.text
			let full = NSRange(text.startIndex..<text.endIndex, in: text)
			for match in regex.matches(in: text, range: full) {
				guard let range = Range(match.range, in: text) else { continue }
				let offset = text.distance(from: text.startIndex, to: range.lowerBound)
				guard let slice = matchedBody(in: text, fromOffset: offset) else {
					throw ScanError(
						message: "unbalanced braces slicing `\(typeName)` in \(source.name)")
				}
				out.append(slice)
			}
		}
		guard !out.isEmpty else {
			throw ScanError(
				message: """
					no declaration or extension of `\(typeName)` exists in the app sources — the guarded \
					type was renamed or removed.
					""")
		}
		return out.joined(separator: "\n")
	}

	/// The brace-matched body of `anchor` inside `typeName`'s whole surface. Disambiguates members
	/// that several types share (`private var footer: some View` lives on both faces).
	static func member(_ anchor: String, of typeName: String) throws -> String {
		let surface = try typeSurface(typeName)
		guard surface.contains(anchor) else {
			throw ScanError(
				message: "`\(typeName)` no longer declares `\(anchor)` — the guarded member moved or was renamed")
		}
		let repeats = surface.components(separatedBy: anchor).count - 1
		guard repeats == 1 else {
			throw ScanError(
				message: "`\(anchor)` appears \(repeats) times inside `\(typeName)` — use a longer anchor")
		}
		return try body(of: anchor, in: surface, origin: typeName)
	}

	// MARK: - Brace matching

	private static func body(of anchor: String, in text: String, origin: String) throws -> String {
		guard let range = text.range(of: anchor) else {
			throw ScanError(message: "`\(anchor)` not found in \(origin)")
		}
		let offset = text.distance(from: text.startIndex, to: range.lowerBound)
		guard let slice = matchedBody(in: text, fromOffset: offset) else {
			throw ScanError(
				message: "could not brace-match the body of `\(anchor)` in \(origin) — unbalanced braces?")
		}
		return slice
	}

	/// Returns the text from `start` through the `}` that closes the first `{` at or after it.
	private static func matchedBody(in text: String, fromOffset start: Int) -> String? {
		let chars = Array(text)
		guard start < chars.count else { return nil }
		var index = start
		var depth = 0
		var opened = false
		while index < chars.count {
			let char = chars[index]
			if char == "/", index + 1 < chars.count, chars[index + 1] == "/" {
				while index < chars.count, chars[index] != "\n" { index += 1 }
				continue
			}
			if char == "/", index + 1 < chars.count, chars[index + 1] == "*" {
				index = skipBlockComment(chars, from: index)
				continue
			}
			if char == "\"" {
				index = skipStringLiteral(chars, from: index)
				continue
			}
			if char == "{" {
				depth += 1
				opened = true
			} else if char == "}" {
				depth -= 1
				if opened, depth == 0 { return String(chars[start...index]) }
			}
			index += 1
		}
		return nil
	}

	/// Swift block comments nest, so this counts depth rather than stopping at the first `*/`.
	private static func skipBlockComment(_ chars: [Character], from start: Int) -> Int {
		var index = start + 2
		var nesting = 1
		while index < chars.count, nesting > 0 {
			if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "*" {
				nesting += 1
				index += 2
				continue
			}
			if chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "/" {
				nesting -= 1
				index += 2
				continue
			}
			index += 1
		}
		return index
	}

	private static func skipStringLiteral(_ chars: [Character], from start: Int) -> Int {
		if start + 2 < chars.count, chars[start + 1] == "\"", chars[start + 2] == "\"" {
			var index = start + 3
			while index + 2 < chars.count {
				if chars[index] == "\\" {
					index += 2
					continue
				}
				if chars[index] == "\"", chars[index + 1] == "\"", chars[index + 2] == "\"" {
					return index + 3
				}
				index += 1
			}
			return chars.count
		}
		var index = start + 1
		while index < chars.count {
			if chars[index] == "\\" {
				index += 2
				continue
			}
			if chars[index] == "\"" { return index + 1 }
			// An unterminated literal would otherwise swallow the rest of the file.
			if chars[index] == "\n" { return index }
			index += 1
		}
		return chars.count
	}
}
